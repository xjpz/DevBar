import Foundation

public struct MimoUsageResponse: Codable, Sendable, Equatable {
    public let code: Int?
    public let message: String?
    public let data: MimoUsageData?

    public init(code: Int?, message: String?, data: MimoUsageData?) {
        self.code = code
        self.message = message
        self.data = data
    }
}

public struct MimoUsageData: Codable, Sendable, Equatable {
    public let monthUsage: MimoMonthUsage?

    public init(monthUsage: MimoMonthUsage?) {
        self.monthUsage = monthUsage
    }
}

public struct MimoMonthUsage: Codable, Sendable, Equatable {
    public let percent: FlexibleDouble?
    public let items: [MimoUsageItem]?

    public init(percent: FlexibleDouble?, items: [MimoUsageItem]?) {
        self.percent = percent
        self.items = items
    }
}

public struct MimoUsageItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }

    public let name: String
    public let used: FlexibleInt?
    public let limit: FlexibleInt?
    public let percent: FlexibleDouble?

    public init(name: String, used: FlexibleInt?, limit: FlexibleInt?, percent: FlexibleDouble?) {
        self.name = name
        self.used = used
        self.limit = limit
        self.percent = percent
    }

    public var usedValue: Int {
        used?.value ?? 0
    }

    public var limitValue: Int {
        limit?.value ?? 0
    }

    public var remainingValue: Int {
        max(limitValue - usedValue, 0)
    }

    public var percentage: Int {
        guard limitValue > 0 else { return 0 }
        let raw = (Double(usedValue) / Double(limitValue) * 100).rounded()
        return min(max(Int(raw), 0), 100)
    }
}

public struct MimoPlanDetailResponse: Codable, Sendable, Equatable {
    public let code: Int?
    public let message: String?
    public let data: MimoPlanDetail?

    public init(code: Int?, message: String?, data: MimoPlanDetail?) {
        self.code = code
        self.message = message
        self.data = data
    }
}

public struct MimoPlanDetail: Codable, Sendable, Equatable {
    public let planCode: String?
    public let planName: String?
    public let currentPeriodEnd: String?
    public let expired: Bool?

    public init(planCode: String?, planName: String?, currentPeriodEnd: String?, expired: Bool?) {
        self.planCode = planCode
        self.planName = planName
        self.currentPeriodEnd = currentPeriodEnd
        self.expired = expired
    }

    public var currentPeriodEndDate: Date? {
        guard let currentPeriodEnd else { return nil }
        return Self.dateFormatter.date(from: currentPeriodEnd)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

public struct FlexibleInt: Codable, Sendable, Equatable {
    public let value: Int

    public init(_ value: Int) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self.value = value
        } else if let value = try? container.decode(Double.self) {
            self.value = Int(value)
        } else if let string = try? container.decode(String.self),
                  let value = Double(string) {
            self.value = Int(value)
        } else {
            self.value = 0
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

public struct FlexibleDouble: Codable, Sendable, Equatable {
    public let value: Double

    public init(_ value: Double) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Double.self) {
            self.value = value
        } else if let value = try? container.decode(Int.self) {
            self.value = Double(value)
        } else if let string = try? container.decode(String.self),
                  let value = Double(string) {
            self.value = value
        } else {
            self.value = 0
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

public extension MimoUsageResponse {
    var usageItems: [MimoUsageItem] {
        data?.monthUsage?.items ?? []
    }

    var quotaRows: [QuotaRowItem] {
        usageItems
            .filter { $0.limitValue > 0 }
            .map { item in
                QuotaRowItem(
                    name: item.displayName,
                    percentage: item.percentage,
                    resetTime: nil,
                    unitDescription: "\(item.usedValue.formattedTokenCount) / \(item.limitValue.formattedTokenCount) tokens"
                )
            }
    }
}

public extension MimoUsageItem {
    var displayName: String {
        switch name {
        case "month_total_token":
            return CoreL10n.text("mimo_monthly_token_quota")
        default:
            return name
        }
    }
}

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
