import Crypto
import Foundation
import NIOSSH
import OSLog
import OpenSSHBcrypt
import _CryptoExtras

public enum TerminalPrivateKeyParserError: Error, Equatable, LocalizedError, Sendable {
    case invalidPEM
    case invalidOpenSSHKey
    case encryptedPrivateKeyUnsupported(String)
    case missingPassphrase
    case incorrectPassphrase
    case invalidKeyDerivation
    case unsupportedKeyType(String)
    case publicKeyMismatch

    public var errorDescription: String? {
        switch self {
        case .invalidPEM:
            return "Invalid OpenSSH private key."
        case .invalidOpenSSHKey:
            return "Invalid OpenSSH private key payload."
        case let .encryptedPrivateKeyUnsupported(cipherName):
            return "Encrypted SSH private keys using \(cipherName) are not supported yet."
        case .missingPassphrase:
            return "SSH private key passphrase is required for this encrypted key."
        case .incorrectPassphrase:
            return "SSH private key passphrase is incorrect."
        case .invalidKeyDerivation:
            return "Unable to decrypt SSH private key."
        case let .unsupportedKeyType(type):
            return "Unsupported SSH private key type: \(type)."
        case .publicKeyMismatch:
            return "The SSH private key does not match its public key."
        }
    }
}

public enum TerminalPrivateKeyParser {
    private static let logger = Logger(subsystem: "DevBarCore", category: "TerminalPrivateKeyParser")

    public static func isEncrypted(_ pem: String) throws -> Bool {
        let header = try readOpenSSHHeader(pem)
        return !(header.cipherName == "none" && header.kdfName == "none")
    }

    public static func parse(_ pem: String, passphrase: String? = nil) throws -> NIOSSHPrivateKey {
        let header = try readOpenSSHHeader(pem)
        let passphraseProvided = passphrase != nil ? "true" : "false"
        let passphraseEmpty = (passphrase ?? "").isEmpty ? "true" : "false"

        logger.debug(
            "Parsing OpenSSH key cipher=\(header.cipherName, privacy: .public) kdf=\(header.kdfName, privacy: .public) passphraseProvided=\(passphraseProvided, privacy: .public) passphraseEmpty=\(passphraseEmpty, privacy: .public)"
        )

        if header.cipherName == "none", header.kdfName == "none" {
            return try parsePrivateBlob(header.privateBlob, wasEncrypted: false)
        }

        guard header.cipherName == "aes256-ctr", header.kdfName == "bcrypt" else {
            throw TerminalPrivateKeyParserError.encryptedPrivateKeyUnsupported(header.cipherName)
        }
        guard let passphrase else {
            throw TerminalPrivateKeyParserError.missingPassphrase
        }
        do {
            let decryptedBlob = try decryptPrivateBlob(
                header.privateBlob,
                kdfOptions: header.kdfOptions,
                passphrase: passphrase
            )
            return try parsePrivateBlob(decryptedBlob, wasEncrypted: true)
        } catch {
            let passphraseEmpty = passphrase.isEmpty ? "true" : "false"
            logger.error(
                "Failed to decrypt OpenSSH key cipher=\(header.cipherName, privacy: .public) kdf=\(header.kdfName, privacy: .public) passphraseProvided=true passphraseEmpty=\(passphraseEmpty, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
            throw error
        }
    }

    private static func readOpenSSHHeader(_ pem: String) throws -> OpenSSHKeyHeader {
        let data = try decodePEM(pem)
        var reader = SSHBinaryReader(data)

        guard reader.readMagic() == Data("openssh-key-v1\0".utf8),
              let cipherName = reader.readString(),
              let kdfName = reader.readString(),
              let kdfOptions = reader.readBytes(),
              let keyCount = reader.readUInt32(),
              keyCount == 1,
              let _ = reader.readBytes(),
              let privateBlob = reader.readBytes(),
              reader.isAtEnd else {
            throw TerminalPrivateKeyParserError.invalidOpenSSHKey
        }

        return OpenSSHKeyHeader(
            cipherName: cipherName,
            kdfName: kdfName,
            kdfOptions: kdfOptions,
            privateBlob: privateBlob
        )
    }

    private static func decodePEM(_ pem: String) throws -> Data {
        let lines = pem
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("-----") }
        guard !lines.isEmpty,
              let data = Data(base64Encoded: lines.joined()) else {
            throw TerminalPrivateKeyParserError.invalidPEM
        }
        return data
    }

    private static func decryptPrivateBlob(_ data: Data, kdfOptions: Data, passphrase: String) throws -> Data {
        var kdfReader = SSHBinaryReader(kdfOptions)
        guard let salt = kdfReader.readBytes(),
              let rounds = kdfReader.readUInt32(),
              kdfReader.isAtEnd else {
            throw TerminalPrivateKeyParserError.invalidOpenSSHKey
        }

        let keySize = 32
        let ivSize = 16
        let keyMaterial = try bcryptPBKDF(
            passphrase: passphrase,
            salt: salt,
            keyLength: keySize + ivSize,
            rounds: rounds
        )
        let key = SymmetricKey(data: keyMaterial.prefix(keySize))
        let iv = keyMaterial.dropFirst(keySize)
        let nonce = try AES._CTR.Nonce(nonceBytes: iv)
        return try AES._CTR.decrypt(data, using: key, nonce: nonce)
    }

    private static func bcryptPBKDF(
        passphrase: String,
        salt: Data,
        keyLength: Int,
        rounds: UInt32
    ) throws -> Data {
        var key = Data(repeating: 0, count: keyLength)
        let passphraseData = Data(passphrase.utf8)
        let status = key.withUnsafeMutableBytes { keyBytes in
            passphraseData.withUnsafeBytes { passphraseBytes in
                salt.withUnsafeBytes { saltBytes in
                    devbar_bcrypt_pbkdf(
                        passphraseBytes.bindMemory(to: CChar.self).baseAddress,
                        passphraseData.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        keyBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyLength,
                        rounds
                    )
                }
            }
        }
        guard status == 0 else {
            throw TerminalPrivateKeyParserError.invalidKeyDerivation
        }
        return key
    }

    private static func parsePrivateBlob(_ data: Data, wasEncrypted: Bool) throws -> NIOSSHPrivateKey {
        var reader = SSHBinaryReader(data)
        guard let check1 = reader.readUInt32(),
              let check2 = reader.readUInt32() else {
            throw TerminalPrivateKeyParserError.invalidOpenSSHKey
        }
        guard check1 == check2 else {
            throw wasEncrypted
                ? TerminalPrivateKeyParserError.incorrectPassphrase
                : TerminalPrivateKeyParserError.invalidOpenSSHKey
        }
        guard
              let keyType = reader.readString(),
              let publicKey = reader.readBytes(),
              let privateKey = reader.readBytes(),
              reader.readString() != nil else {
            throw TerminalPrivateKeyParserError.invalidOpenSSHKey
        }

        logger.debug("Parsed OpenSSH private key type=\(keyType, privacy: .public) encrypted=\(wasEncrypted, privacy: .public)")

        guard keyType == "ssh-ed25519" else {
            throw TerminalPrivateKeyParserError.unsupportedKeyType(keyType)
        }
        guard publicKey.count == 32, privateKey.count >= 64 else {
            throw TerminalPrivateKeyParserError.invalidOpenSSHKey
        }

        let seed = privateKey.prefix(32)
        let parsed = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        guard Data(parsed.publicKey.rawRepresentation) == publicKey else {
            throw TerminalPrivateKeyParserError.publicKeyMismatch
        }
        return NIOSSHPrivateKey(ed25519Key: parsed)
    }
}

private struct OpenSSHKeyHeader {
    let cipherName: String
    let kdfName: String
    let kdfOptions: Data
    let privateBlob: Data
}

private struct SSHBinaryReader {
    private let data: Data
    private var offset = 0

    init(_ data: Data) {
        self.data = data
    }

    var isAtEnd: Bool {
        offset == data.count
    }

    mutating func readMagic() -> Data? {
        let magic = Data("openssh-key-v1\0".utf8)
        guard data.count >= magic.count,
              data.prefix(magic.count) == magic else {
            return nil
        }
        offset = magic.count
        return magic
    }

    mutating func readUInt32() -> UInt32? {
        guard offset + 4 <= data.count else { return nil }
        let value = data[offset..<offset + 4].reduce(UInt32(0)) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
        offset += 4
        return value
    }

    mutating func readString() -> String? {
        guard let bytes = readBytes() else { return nil }
        return String(data: bytes, encoding: .utf8)
    }

    mutating func readBytes() -> Data? {
        guard let length = readUInt32(),
              length <= UInt32(data.count) else {
            return nil
        }
        let count = Int(length)
        guard offset + count <= data.count else { return nil }
        let bytes = data[offset..<offset + count]
        offset += count
        return Data(bytes)
    }
}
