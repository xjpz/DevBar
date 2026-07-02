import Foundation
import SwiftUI

public enum QuotaProvider: String, CaseIterable, Codable, Sendable {
    case glm
    case openai
    case mimo
    case deepseek

    public var localizedName: String {
        switch self {
        case .glm: return "GLM"
        case .openai: return "OpenAI"
        case .mimo: return "MiMo"
        case .deepseek: return "DeepSeek"
        }
    }

    public var iconName: String {
        switch self {
        case .glm: return "sparkles"
        case .openai: return "circle.hexagon"
        case .mimo: return "bolt.hexagon"
        case .deepseek: return "waveform.path.ecg"
        }
    }

    public var assetName: String {
        switch self {
        case .glm: return "GLM"
        case .openai: return "OpenAI"
        case .mimo: return "MiMo"
        case .deepseek: return "DeepSeek"
        }
    }

    public var accentColor: Color {
        switch self {
        case .glm: return Color(red: 0.14, green: 0.59, blue: 0.93)
        case .openai: return Color(red: 0.12, green: 0.69, blue: 0.54)
        case .mimo: return Color(red: 1.0, green: 0.42, blue: 0.08)
        case .deepseek: return Color(red: 0.35, green: 0.43, blue: 0.98)
        }
    }
}

public struct AccountConfig: Codable, Sendable, Identifiable, Equatable {
    public var id: String { provider.rawValue }

    public let provider: QuotaProvider
    public var isEnabled: Bool
    public var order: Int

    public init(provider: QuotaProvider, isEnabled: Bool, order: Int) {
        self.provider = provider
        self.isEnabled = isEnabled
        self.order = order
    }
}

public struct ProviderCredentialRef: Codable, Sendable, Equatable {
    public let namespace: String
    public let keychainAccount: String

    public init(namespace: String = "providerAccount", keychainAccount: String) {
        self.namespace = namespace
        self.keychainAccount = keychainAccount
    }
}

public struct ProviderAccountSyncPolicy: Codable, Sendable, Equatable {
    public var quotaSyncEnabled: Bool
    public var credentialSyncEnabled: Bool

    public init(quotaSyncEnabled: Bool = true, credentialSyncEnabled: Bool = false) {
        self.quotaSyncEnabled = quotaSyncEnabled
        self.credentialSyncEnabled = credentialSyncEnabled
    }
}

public struct ProviderAccount: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public var provider: QuotaProvider
    public var displayName: String
    public var isEnabled: Bool
    public var order: Int
    public var credentialRef: ProviderCredentialRef
    public var providerAccountIdentifier: String?
    public var syncPolicy: ProviderAccountSyncPolicy
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString.lowercased(),
        provider: QuotaProvider,
        displayName: String? = nil,
        isEnabled: Bool,
        order: Int,
        credentialRef: ProviderCredentialRef? = nil,
        providerAccountIdentifier: String? = nil,
        syncPolicy: ProviderAccountSyncPolicy = ProviderAccountSyncPolicy(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.provider = provider
        self.displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? provider.localizedName
        self.isEnabled = isEnabled
        self.order = order
        self.credentialRef = credentialRef ?? ProviderCredentialRef(
            keychainAccount: DevBarCoreConstants.Keychain.providerAccountCredentialKey(for: id)
        )
        self.providerAccountIdentifier = providerAccountIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.syncPolicy = syncPolicy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var legacyConfig: AccountConfig {
        AccountConfig(provider: provider, isEnabled: isEnabled, order: order)
    }

    public static func migratedID(for provider: QuotaProvider) -> String {
        "legacy-\(provider.rawValue)"
    }
}

public struct ProviderCredentialEnvelope: Codable, Sendable, Equatable {
    public let accountID: String
    public let provider: QuotaProvider
    public var token: String?
    public var cookieString: String?
    public var accountIdentifier: String?
    public var issuedAt: Date?
    public var expiresAt: Date?
    public var revision: Int
    public var updatedAt: Date

    public init(
        accountID: String,
        provider: QuotaProvider,
        token: String? = nil,
        cookieString: String? = nil,
        accountIdentifier: String? = nil,
        issuedAt: Date? = nil,
        expiresAt: Date? = nil,
        revision: Int = 1,
        updatedAt: Date = Date()
    ) {
        self.accountID = accountID
        self.provider = provider
        self.token = token?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.cookieString = cookieString?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.accountIdentifier = accountIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.revision = revision
        self.updatedAt = updatedAt
    }

    public var hasCredential: Bool {
        token?.isEmpty == false || cookieString?.isEmpty == false
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

public struct OpenAIUsageResponse: Codable, Sendable, Equatable {
    public let planType: String?
    public let rateLimit: OpenAIRateLimit?
    public let rateLimitResetCredits: OpenAIRateLimitResetCredits?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case rateLimitResetCredits = "rate_limit_reset_credits"
    }

    public init(
        planType: String?,
        rateLimit: OpenAIRateLimit?,
        rateLimitResetCredits: OpenAIRateLimitResetCredits? = nil
    ) {
        self.planType = planType
        self.rateLimit = rateLimit
        self.rateLimitResetCredits = rateLimitResetCredits
    }

    public var availableResetCount: Int? {
        rateLimitResetCredits?.availableCount
    }

    public var displayPlanType: String? {
        Self.displayPlanType(for: planType)
    }

    public static func displayPlanType(for rawValue: String?) -> String? {
        guard let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        switch trimmed.lowercased() {
        case "prolite":
            return "Pro"
        default:
            return trimmed.capitalized
        }
    }
}

public struct OpenAIRateLimit: Codable, Sendable, Equatable {
    public let allowed: Bool?
    public let limitReached: Bool?
    public let primaryWindow: OpenAIUsageWindow?
    public let secondaryWindow: OpenAIUsageWindow?

    enum CodingKeys: String, CodingKey {
        case allowed
        case limitReached = "limit_reached"
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }

    public init(
        allowed: Bool?,
        limitReached: Bool?,
        primaryWindow: OpenAIUsageWindow?,
        secondaryWindow: OpenAIUsageWindow?
    ) {
        self.allowed = allowed
        self.limitReached = limitReached
        self.primaryWindow = primaryWindow
        self.secondaryWindow = secondaryWindow
    }
}

public struct OpenAIUsageWindow: Codable, Sendable, Equatable {
    public let usedPercent: Int
    public let limitWindowSeconds: Int?
    public let resetAfterSeconds: Int?
    public let resetAt: Int?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAfterSeconds = "reset_after_seconds"
        case resetAt = "reset_at"
    }

    public init(
        usedPercent: Int,
        limitWindowSeconds: Int?,
        resetAfterSeconds: Int?,
        resetAt: Int?
    ) {
        self.usedPercent = usedPercent
        self.limitWindowSeconds = limitWindowSeconds
        self.resetAfterSeconds = resetAfterSeconds
        self.resetAt = resetAt
    }

    public var displayName: String {
        guard let seconds = limitWindowSeconds else { return "" }
        let hours = seconds / 3600
        if hours >= 168 {
            return CoreL10n.text("openai_weekly")
        } else if hours >= 24 {
            return CoreL10n.text("openai_daily")
        } else {
            return String(format: CoreL10n.text("openai_session"), Int(hours))
        }
    }

    public var formattedResetTime: String? {
        guard let resetAt else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(resetAt))
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }
}

public struct OpenAIRateLimitResetCredits: Codable, Sendable, Equatable {
    public let availableCount: Int

    enum CodingKeys: String, CodingKey {
        case availableCount = "available_count"
    }

    public init(availableCount: Int) {
        self.availableCount = availableCount
    }
}
