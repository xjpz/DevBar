import Foundation

// MARK: - DeepSeek Platform Usage API Response

public struct DeepSeekUsageResponse: Codable, Sendable, Equatable {
    public let code: Int?
    public let msg: String?
    public let data: DeepSeekBizWrapper?

    public init(code: Int?, msg: String?, data: DeepSeekBizWrapper?) {
        self.code = code
        self.msg = msg
        self.data = data
    }
}

public struct DeepSeekBizWrapper: Codable, Sendable, Equatable {
    public let bizCode: Int?
    public let bizMsg: String?
    public let bizData: DeepSeekUsageData?

    enum CodingKeys: String, CodingKey {
        case bizCode = "biz_code"
        case bizMsg = "biz_msg"
        case bizData = "biz_data"
    }

    public init(bizCode: Int?, bizMsg: String?, bizData: DeepSeekUsageData?) {
        self.bizCode = bizCode
        self.bizMsg = bizMsg
        self.bizData = bizData
    }
}

public struct DeepSeekUsageData: Codable, Sendable, Equatable {
    public let currentToken: Int?
    public let monthlyUsage: Int?
    public let totalUsage: Int?
    public let normalWallets: [DeepSeekWallet]?
    public let bonusWallets: [DeepSeekWallet]?
    public let totalAvailableTokenEstimation: String?
    public let monthlyCosts: [DeepSeekMonthlyCost]?
    public let monthlyTokenUsage: Int?

    enum CodingKeys: String, CodingKey {
        case currentToken = "current_token"
        case monthlyUsage = "monthly_usage"
        case totalUsage = "total_usage"
        case normalWallets = "normal_wallets"
        case bonusWallets = "bonus_wallets"
        case totalAvailableTokenEstimation = "total_available_token_estimation"
        case monthlyCosts = "monthly_costs"
        case monthlyTokenUsage = "monthly_token_usage"
    }

    public init(
        currentToken: Int?,
        monthlyUsage: Int?,
        totalUsage: Int?,
        normalWallets: [DeepSeekWallet]?,
        bonusWallets: [DeepSeekWallet]?,
        totalAvailableTokenEstimation: String?,
        monthlyCosts: [DeepSeekMonthlyCost]?,
        monthlyTokenUsage: Int?
    ) {
        self.currentToken = currentToken
        self.monthlyUsage = monthlyUsage
        self.totalUsage = totalUsage
        self.normalWallets = normalWallets
        self.bonusWallets = bonusWallets
        self.totalAvailableTokenEstimation = totalAvailableTokenEstimation
        self.monthlyCosts = monthlyCosts
        self.monthlyTokenUsage = monthlyTokenUsage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currentToken = try container.decodeIfPresent(Int.self, forKey: .currentToken)
        monthlyUsage = try container.decodeIntegerOrStringIfPresent(forKey: .monthlyUsage)
        totalUsage = try container.decodeIfPresent(Int.self, forKey: .totalUsage)
        normalWallets = try container.decodeIfPresent([DeepSeekWallet].self, forKey: .normalWallets)
        bonusWallets = try container.decodeIfPresent([DeepSeekWallet].self, forKey: .bonusWallets)
        totalAvailableTokenEstimation = try container.decodeIfPresent(
            String.self,
            forKey: .totalAvailableTokenEstimation
        )
        monthlyCosts = try container.decodeIfPresent([DeepSeekMonthlyCost].self, forKey: .monthlyCosts)
        monthlyTokenUsage = try container.decodeIntegerOrStringIfPresent(forKey: .monthlyTokenUsage)
    }

    // MARK: - Computed helpers

    /// Total wallet balance (normal + bonus) in CNY.
    public var totalBalanceCNY: Double {
        let normal = normalWallets?.reduce(0.0) { $0 + ($1.balance.flatMap(Double.init) ?? 0) } ?? 0
        let bonus = bonusWallets?.reduce(0.0) { $0 + ($1.balance.flatMap(Double.init) ?? 0) } ?? 0
        return normal + bonus
    }

    /// Total available token estimation from all wallets.
    public var totalAvailableTokens: Int {
        Int(totalAvailableTokenEstimation ?? "0") ?? 0
    }

    /// Monthly cost in CNY.
    public var monthlyCostCNY: Double {
        monthlyCosts?.reduce(0.0) { $0 + ($1.amount.flatMap(Double.init) ?? 0) } ?? 0
    }

    /// Monthly token usage.
    public var monthlyTokenUsageValue: Int {
        monthlyTokenUsage ?? 0
    }

    /// Cost usage percentage: monthlyCost / (totalBalance + monthlyCost) * 100
    public var costPercentage: Int {
        let spent = monthlyCostCNY
        let total = totalBalanceCNY + spent
        guard total > 0 else { return 0 }
        return min(Int((spent / total * 100).rounded()), 100)
    }

    /// Token usage percentage: monthlyTokenUsage / (totalAvailableTokens + monthlyTokenUsage) * 100
    public var tokenPercentage: Int {
        let used = monthlyTokenUsageValue
        let total = totalAvailableTokens + used
        guard total > 0 else { return 0 }
        return min(Int((Double(used) / Double(total) * 100).rounded()), 100)
    }

    /// Convert to QuotaRowItem list for display.
    public var quotaRows: [QuotaRowItem] {
        var rows: [QuotaRowItem] = []

        // Cost row
        let spentCNY = monthlyCostCNY
        let totalCNY = totalBalanceCNY + spentCNY
        if totalCNY > 0 {
            rows.append(QuotaRowItem(
                name: CoreL10n.text("deepseek_cost_usage"),
                percentage: costPercentage,
                resetTime: nil,
                unitDescription: "\u{00a5}\(String(format: "%.4f", spentCNY)) / \u{00a5}\(String(format: "%.2f", totalCNY))"
            ))
        }

        // Token row
        let usedTokens = monthlyTokenUsageValue
        let totalTokens = totalAvailableTokens + usedTokens
        if totalTokens > 0 {
            rows.append(QuotaRowItem(
                name: CoreL10n.text("deepseek_token_usage"),
                percentage: tokenPercentage,
                resetTime: nil,
                unitDescription: "\(usedTokens.formattedTokenCount) / \(totalTokens.formattedTokenCount) tokens"
            ))
        }

        return rows
    }
}

private extension KeyedDecodingContainer {
    func decodeIntegerOrStringIfPresent(forKey key: Key) throws -> Int? {
        guard contains(key), try !decodeNil(forKey: key) else {
            return nil
        }
        if let value = try? decode(Int.self, forKey: key) {
            return value
        }
        if let string = try? decode(String.self, forKey: key),
           let value = Int(string) {
            return value
        }

        throw DecodingError.typeMismatch(
            Int.self,
            DecodingError.Context(
                codingPath: codingPath + [key],
                debugDescription: "Expected an integer or an integer string"
            )
        )
    }
}

public struct DeepSeekWallet: Codable, Sendable, Equatable {
    public let currency: String?
    public let balance: String?
    public let tokenEstimation: String?

    enum CodingKeys: String, CodingKey {
        case currency
        case balance
        case tokenEstimation = "token_estimation"
    }

    public init(currency: String?, balance: String?, tokenEstimation: String?) {
        self.currency = currency
        self.balance = balance
        self.tokenEstimation = tokenEstimation
    }
}

public struct DeepSeekMonthlyCost: Codable, Sendable, Equatable {
    public let currency: String?
    public let amount: String?

    public init(currency: String?, amount: String?) {
        self.currency = currency
        self.amount = amount
    }
}

// MARK: - Token count formatting

private extension Int {
    var formattedTokenCount: String {
        let value = Double(self)
        if abs(value) >= 1_000_000_000 {
            return String(format: "%.1fB", value / 1_000_000_000)
        }
        if abs(value) >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        }
        if abs(value) >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        return "\(self)"
    }
}
