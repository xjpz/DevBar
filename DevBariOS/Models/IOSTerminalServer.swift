import DevBarCore
import Foundation
import SwiftData

@Model
final class IOSTerminalServer {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var authMethodRawValue: String
    var remoteOSFamilyRawValue: String?
    var passwordSecretKey: String?
    var privateKeySecretKey: String?
    var privateKeyPassphraseSecretKey: String?
    var createdAt: Date
    var updatedAt: Date
    var lastConnectedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 22,
        username: String,
        authMethod: IOSTerminalAuthMethod = .password,
        remoteOSFamily: TerminalRemoteOSFamily = .auto,
        passwordSecretKey: String? = nil,
        privateKeySecretKey: String? = nil,
        privateKeyPassphraseSecretKey: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastConnectedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.authMethodRawValue = authMethod.rawValue
        self.remoteOSFamilyRawValue = remoteOSFamily.rawValue
        self.passwordSecretKey = passwordSecretKey
        self.privateKeySecretKey = privateKeySecretKey
        self.privateKeyPassphraseSecretKey = privateKeyPassphraseSecretKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastConnectedAt = lastConnectedAt
    }
}

extension IOSTerminalServer {
    var authMethod: IOSTerminalAuthMethod {
        get { IOSTerminalAuthMethod(rawValue: authMethodRawValue) ?? .password }
        set { authMethodRawValue = newValue.rawValue }
    }

    var displayAddress: String {
        "\(username)@\(host):\(port)"
    }

    var remoteOSFamily: TerminalRemoteOSFamily {
        get {
            guard let remoteOSFamilyRawValue else { return .auto }
            return TerminalRemoteOSFamily(rawValue: remoteOSFamilyRawValue) ?? .auto
        }
        set {
            remoteOSFamilyRawValue = newValue.rawValue
        }
    }
}

enum IOSTerminalAuthMethod: String, CaseIterable, Identifiable {
    case password
    case privateKey

    var id: String { rawValue }

    var title: String {
        switch self {
        case .password:
            return "Password"
        case .privateKey:
            return "SSH Key"
        }
    }

    var systemImage: String {
        switch self {
        case .password:
            return "key.fill"
        case .privateKey:
            return "doc.text.fill"
        }
    }
}
