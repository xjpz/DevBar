import CryptoKit
import Foundation

struct ClipboardPacket: Codable, Sendable {
    enum Kind: String, Codable { case hello, helloAck, request, response, error }
    var kind: Kind
    var nonce: Data?
    var request: ClipboardRequest?
    var response: ClipboardResponse?
    var failure: ClipboardFailure?
}

struct ClipboardEnvelope: Codable, Sendable {
    var version = 1
    var sessionID: String
    var sequence: UInt64
    var bootstrap: Bool
    var sealed: Data
}

enum ClipboardSharingCodec {
    static let maximumWireBytes = 64 * 1024

    static func key(secret: String, from: String, to: String, salt: Data = Data()) throws -> SymmetricKey {
        // Pair secrets are 32 random bytes encoded as base64url; old/malformed pairs must be replaced.
        let base64 = secret.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padded = base64 + String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let bytes = Data(base64Encoded: padded), bytes.count == 32,
              bytes.contains(where: { $0 != 0 }), from != to else { throw ClipboardFailure.rePair }
        let context = try JSONEncoder().encode(["DevBar.clipboard.v1", from, to])
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: bytes), salt: salt,
                                      info: context, outputByteCount: 32)
    }

    private static func aad(from: String, to: String, requestID: String, envelope: ClipboardEnvelope) throws -> Data {
        try JSONEncoder().encode(["1", from, to, requestID, envelope.sessionID,
                                  String(envelope.sequence), envelope.bootstrap ? "bootstrap" : "session"])
    }

    static func seal(_ packet: ClipboardPacket, key: SymmetricKey, from: String, to: String,
                     requestID: String, sessionID: String, sequence: UInt64, bootstrap: Bool) throws -> String {
        var envelope = ClipboardEnvelope(sessionID: sessionID, sequence: sequence, bootstrap: bootstrap, sealed: Data())
        let box = try AES.GCM.seal(JSONEncoder().encode(packet), using: key,
                                   authenticating: aad(from: from, to: to, requestID: requestID, envelope: envelope))
        guard let sealed = box.combined else { throw ClipboardFailure.invalidMessage }
        envelope.sealed = sealed
        let encoded = try JSONEncoder().encode(envelope).base64EncodedString()
        // Check the actual outer JSON too; this bound includes Base64 and routing overhead.
        let message = DeviceRelayMessage(type: .clipboardSecure, requestId: requestID, fromDeviceId: from,
                                        targetDeviceId: to, payload: ["encoded": encoded])
        guard try DeviceRelayMessageCodec.encode(message).utf8.count <= maximumWireBytes else {
            throw ClipboardFailure.tooLarge
        }
        return encoded
    }

    static func envelope(_ encoded: String) throws -> ClipboardEnvelope {
        guard encoded.utf8.count <= maximumWireBytes, let data = Data(base64Encoded: encoded) else {
            throw ClipboardFailure.invalidMessage
        }
        let envelope = try JSONDecoder().decode(ClipboardEnvelope.self, from: data)
        guard envelope.version == 1, envelope.sessionID.utf8.count <= 128 else { throw ClipboardFailure.unsupported }
        return envelope
    }

    static func open(_ envelope: ClipboardEnvelope, key: SymmetricKey, from: String, to: String,
                     requestID: String) throws -> ClipboardPacket {
        let box = try AES.GCM.SealedBox(combined: envelope.sealed)
        let data = try AES.GCM.open(box, using: key,
                                    authenticating: aad(from: from, to: to, requestID: requestID, envelope: envelope))
        return try JSONDecoder().decode(ClipboardPacket.self, from: data)
    }
}

struct ClipboardReplayWindow {
    private var highest: UInt64 = 0
    private var seen = Set<UInt64>()

    mutating func accept(_ sequence: UInt64) throws {
        guard sequence > 0, !seen.contains(sequence), highest < 128 || sequence > highest - 128 else {
            throw ClipboardFailure.invalidMessage
        }
        highest = max(highest, sequence)
        seen.insert(sequence)
        seen = seen.filter { highest < 128 || $0 > highest - 128 }
    }
}
