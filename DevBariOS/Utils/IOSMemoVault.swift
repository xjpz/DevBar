import Combine
import CryptoKit
import Foundation
import LocalAuthentication

enum IOSSecurityMode: String {
    case none = "none"
    case faceId = "faceId"
    case password = "password"
}

final class IOSMemoVault: ObservableObject {
    @Published var isUnlocked = false
    @Published var isPasswordSet: Bool = false
    @Published var securityMode: IOSSecurityMode = .none

    private var derivedKey: SymmetricKey?
    private static let verifyPlaintext = "DevBarMemoVerifyToken"
    static let maxFailedAttempts = 5

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let verificationSealedBox = "memo.vault.sealedBox"
        static let failedAttempts = "memo.vault.failedAttempts"
        static let hasPassword = "memo.vault.hasPassword"
        static let securityMode = "memo.vault.securityMode"
    }

    private enum KeychainKeys {
        static let service = "com.devbar.memo"
        static let faceIdAccount = "faceid.encryption.key"
    }

    init() {
        let modeRaw = UserDefaults.standard.string(forKey: Keys.securityMode)
        let hasLegacy = UserDefaults.standard.bool(forKey: Keys.hasPassword)

        if let raw = modeRaw, let mode = IOSSecurityMode(rawValue: raw) {
            securityMode = mode
        } else if hasLegacy {
            securityMode = .password
        } else {
            securityMode = .none
        }
        isPasswordSet = securityMode != .none
    }

    // MARK: - Face ID

    enum FaceIdResult {
        case success
        case notAvailable
        case canceled
        case failed(String)
    }

    func setupFaceId() async -> FaceIdResult {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .notAvailable
        }

        do {
            let ok = try await authenticateBiometrics(context: context, reason: String(localized: "ios_memo_faceid_setup_reason"))
            guard ok else { return .canceled }

            let key = SymmetricKey(size: .bits256)
            guard saveKeyToKeychain(key) else { return .failed("Keychain error") }

            derivedKey = key
            applySecurityMode(.faceId)
            return .success
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func unlockWithFaceId() async -> Bool {
        let context = LAContext()
        do {
            let ok = try await authenticateBiometrics(context: context, reason: String(localized: "ios_memo_faceid_unlock_reason"))
            guard ok else { return false }

            guard let keyData = loadKeyFromKeychain() else { return false }
            derivedKey = SymmetricKey(data: keyData)
            isUnlocked = true
            return true
        } catch {
            return false
        }
    }

    // MARK: - Password

    func setPassword(_ password: String) {
        let key = deriveKey(from: password)
        derivedKey = key

        if let sealedBox = try? AES.GCM.seal(Self.verifyPlaintext.data(using: .utf8)!, using: key),
           let boxData = sealedBox.combined {
            defaults.set(boxData, forKey: Keys.verificationSealedBox)
        }

        applySecurityMode(.password)
        defaults.set(true, forKey: Keys.hasPassword)
        defaults.set(0, forKey: Keys.failedAttempts)
    }

    func unlock(with password: String) -> UnlockResult {
        let key = deriveKey(from: password)

        guard let boxData = defaults.data(forKey: Keys.verificationSealedBox),
              let sealedBox = try? AES.GCM.SealedBox(combined: boxData),
              let decrypted = try? AES.GCM.open(sealedBox, using: key),
              String(data: decrypted, encoding: .utf8) == Self.verifyPlaintext else {
            let attempts = defaults.integer(forKey: Keys.failedAttempts) + 1
            defaults.set(attempts, forKey: Keys.failedAttempts)
            if attempts >= Self.maxFailedAttempts { return .destroyed }
            return .wrong
        }

        derivedKey = key
        isUnlocked = true
        defaults.set(0, forKey: Keys.failedAttempts)
        return .success
    }

    // MARK: - Lock / Remove

    func lock() {
        derivedKey = nil
        isUnlocked = false
    }

    func removeSecurity() {
        if securityMode == .faceId {
            deleteKeyFromKeychain()
        }
        derivedKey = nil
        isUnlocked = false
        isPasswordSet = false
        securityMode = .none
        defaults.set(IOSSecurityMode.none.rawValue, forKey: Keys.securityMode)
        defaults.removeObject(forKey: Keys.verificationSealedBox)
        defaults.set(false, forKey: Keys.hasPassword)
        defaults.set(0, forKey: Keys.failedAttempts)
    }

    // MARK: - Encrypt / Decrypt

    func encrypt(_ plaintext: String) -> Data? {
        guard let key = derivedKey else { return nil }
        guard let data = plaintext.data(using: .utf8) else { return nil }
        return (try? AES.GCM.seal(data, using: key))?.combined
    }

    func decrypt(_ encryptedData: Data) -> String? {
        guard let key = derivedKey else { return nil }
        guard let sealedBox = try? AES.GCM.SealedBox(combined: encryptedData) else { return nil }
        guard let decrypted = try? AES.GCM.open(sealedBox, using: key) else { return nil }
        return String(data: decrypted, encoding: .utf8)
    }

    // MARK: - Private helpers

    private func applySecurityMode(_ mode: IOSSecurityMode) {
        securityMode = mode
        isPasswordSet = true
        isUnlocked = true
        defaults.set(mode.rawValue, forKey: Keys.securityMode)
    }

    private func deriveKey(from password: String) -> SymmetricKey {
        let digest = SHA256.hash(data: password.data(using: .utf8) ?? Data())
        return SymmetricKey(data: digest)
    }

    private func authenticateBiometrics(context: LAContext, reason: String) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
                continuation.resume(returning: success)
            }
        }
    }

    // MARK: - Keychain

    private func saveKeyToKeychain(_ key: SymmetricKey) -> Bool {
        deleteKeyFromKeychain()
        let keyData = key.withUnsafeBytes { Data($0) }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: KeychainKeys.service,
            kSecAttrAccount: KeychainKeys.faceIdAccount,
            kSecValueData: keyData,
            kSecAttrAccessible: kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private func loadKeyFromKeychain() -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: KeychainKeys.service,
            kSecAttrAccount: KeychainKeys.faceIdAccount,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private func deleteKeyFromKeychain() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: KeychainKeys.service,
            kSecAttrAccount: KeychainKeys.faceIdAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum UnlockResult {
        case success
        case wrong
        case destroyed
    }
}
