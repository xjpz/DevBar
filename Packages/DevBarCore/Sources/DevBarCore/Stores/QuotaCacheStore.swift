import Foundation

public struct GLMQuotaCacheSnapshot: Codable, Sendable, Equatable {
    public let quotaData: QuotaData?
    public let subscription: Subscription?
    public let lastUpdated: Date?

    public init(quotaData: QuotaData?, subscription: Subscription?, lastUpdated: Date?) {
        self.quotaData = quotaData
        self.subscription = subscription
        self.lastUpdated = lastUpdated
    }
}

public struct OpenAIQuotaCacheSnapshot: Codable, Sendable, Equatable {
    public let usageResponse: OpenAIUsageResponse?
    public let lastUpdated: Date?

    public init(usageResponse: OpenAIUsageResponse?, lastUpdated: Date?) {
        self.usageResponse = usageResponse
        self.lastUpdated = lastUpdated
    }
}

public struct MimoQuotaCacheSnapshot: Codable, Sendable, Equatable {
    public let usageResponse: MimoUsageResponse?
    public let planDetail: MimoPlanDetail?
    public let lastUpdated: Date?
    public let detailLastFetchedAt: Date?

    public init(
        usageResponse: MimoUsageResponse?,
        planDetail: MimoPlanDetail?,
        lastUpdated: Date?,
        detailLastFetchedAt: Date?
    ) {
        self.usageResponse = usageResponse
        self.planDetail = planDetail
        self.lastUpdated = lastUpdated
        self.detailLastFetchedAt = detailLastFetchedAt
    }
}

public struct DeepSeekQuotaCacheSnapshot: Codable, Sendable, Equatable {
    public let usageResponse: DeepSeekUsageResponse?
    public let lastUpdated: Date?

    public init(usageResponse: DeepSeekUsageResponse?, lastUpdated: Date?) {
        self.usageResponse = usageResponse
        self.lastUpdated = lastUpdated
    }
}

public protocol QuotaCacheStore {
    func loadGLMSnapshot() -> GLMQuotaCacheSnapshot?
    func saveGLMSnapshot(_ snapshot: GLMQuotaCacheSnapshot)
    func clearGLMSnapshot()
    func loadOpenAISnapshot() -> OpenAIQuotaCacheSnapshot?
    func saveOpenAISnapshot(_ snapshot: OpenAIQuotaCacheSnapshot)
    func clearOpenAISnapshot()
    func loadMimoSnapshot() -> MimoQuotaCacheSnapshot?
    func saveMimoSnapshot(_ snapshot: MimoQuotaCacheSnapshot)
    func clearMimoSnapshot()
    func loadDeepSeekSnapshot() -> DeepSeekQuotaCacheSnapshot?
    func saveDeepSeekSnapshot(_ snapshot: DeepSeekQuotaCacheSnapshot)
    func clearDeepSeekSnapshot()
}

public struct UserDefaultsQuotaCacheStore: QuotaCacheStore {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
            ?? UserDefaults(suiteName: DevBarCoreConstants.AppGroup.groupID)
            ?? .standard
    }

    public func loadGLMSnapshot() -> GLMQuotaCacheSnapshot? {
        load(GLMQuotaCacheSnapshot.self, forKey: DevBarCoreConstants.Defaults.glmQuotaCacheKey)
    }

    public func saveGLMSnapshot(_ snapshot: GLMQuotaCacheSnapshot) {
        save(snapshot, forKey: DevBarCoreConstants.Defaults.glmQuotaCacheKey)
    }

    public func clearGLMSnapshot() {
        defaults.removeObject(forKey: DevBarCoreConstants.Defaults.glmQuotaCacheKey)
    }

    public func loadOpenAISnapshot() -> OpenAIQuotaCacheSnapshot? {
        load(OpenAIQuotaCacheSnapshot.self, forKey: DevBarCoreConstants.Defaults.openAIQuotaCacheKey)
    }

    public func saveOpenAISnapshot(_ snapshot: OpenAIQuotaCacheSnapshot) {
        save(snapshot, forKey: DevBarCoreConstants.Defaults.openAIQuotaCacheKey)
    }

    public func clearOpenAISnapshot() {
        defaults.removeObject(forKey: DevBarCoreConstants.Defaults.openAIQuotaCacheKey)
    }

    public func loadMimoSnapshot() -> MimoQuotaCacheSnapshot? {
        load(MimoQuotaCacheSnapshot.self, forKey: DevBarCoreConstants.Defaults.mimoQuotaCacheKey)
    }

    public func saveMimoSnapshot(_ snapshot: MimoQuotaCacheSnapshot) {
        save(snapshot, forKey: DevBarCoreConstants.Defaults.mimoQuotaCacheKey)
    }

    public func clearMimoSnapshot() {
        defaults.removeObject(forKey: DevBarCoreConstants.Defaults.mimoQuotaCacheKey)
    }

    public func loadDeepSeekSnapshot() -> DeepSeekQuotaCacheSnapshot? {
        load(DeepSeekQuotaCacheSnapshot.self, forKey: DevBarCoreConstants.Defaults.deepseekQuotaCacheKey)
    }

    public func saveDeepSeekSnapshot(_ snapshot: DeepSeekQuotaCacheSnapshot) {
        save(snapshot, forKey: DevBarCoreConstants.Defaults.deepseekQuotaCacheKey)
    }

    public func clearDeepSeekSnapshot() {
        defaults.removeObject(forKey: DevBarCoreConstants.Defaults.deepseekQuotaCacheKey)
    }

    private func load<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(Value.self, from: data)
    }

    private func save<Value: Encodable>(_ value: Value, forKey key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
