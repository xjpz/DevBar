import Foundation

public struct HomeAssistantTranslationCatalog: Codable, Equatable, Sendable {
    public let language: String
    public let resources: [String: String]

    public init(language: String, resources: [String: String] = [:]) {
        self.language = language
        self.resources = resources
    }

    public var isEmpty: Bool { resources.isEmpty }

    public func stateText(for entity: HomeAssistantEntity, rawState: String? = nil) -> String? {
        let state = rawState ?? entity.state.state
        let deviceClass = entity.deviceClass ?? "_"
        var keys: [String] = []
        if let platform = entity.platform, let translationKey = entity.translationKey {
            keys.append("component.\(platform).entity.\(entity.domain).\(translationKey).state.\(state)")
        }
        keys.append(contentsOf: [
            "component.\(entity.domain).state.\(deviceClass).\(state)",
            "component.\(entity.domain).state._.\(state)",
            "component.\(entity.domain).entity_component.\(deviceClass).state.\(state)",
            "component.\(entity.domain).entity_component._.state.\(state)",
        ])
        return firstValue(for: keys)
    }

    public func attributeName(_ attribute: String, for entity: HomeAssistantEntity) -> String? {
        let deviceClass = entity.deviceClass ?? "_"
        var keys: [String] = []
        if let platform = entity.platform, let translationKey = entity.translationKey {
            keys.append("component.\(platform).entity.\(entity.domain).\(translationKey).state_attributes.\(attribute).name")
        }
        keys.append(contentsOf: [
            "component.\(entity.domain).entity_component.\(deviceClass).state_attributes.\(attribute).name",
            "component.\(entity.domain).entity_component._.state_attributes.\(attribute).name",
        ])
        return firstValue(for: keys)
    }

    public func attributeValue(
        _ rawValue: String,
        attribute: String,
        for entity: HomeAssistantEntity
    ) -> String? {
        let deviceClass = entity.deviceClass ?? "_"
        var keys: [String] = []
        if let platform = entity.platform, let translationKey = entity.translationKey {
            keys.append("component.\(platform).entity.\(entity.domain).\(translationKey).state_attributes.\(attribute).state.\(rawValue)")
        }
        keys.append(contentsOf: [
            "component.\(entity.domain).entity_component.\(deviceClass).state_attributes.\(attribute).state.\(rawValue)",
            "component.\(entity.domain).entity_component._.state_attributes.\(attribute).state.\(rawValue)",
        ])
        return firstValue(for: keys)
    }

    public func merging(_ other: HomeAssistantTranslationCatalog) -> HomeAssistantTranslationCatalog {
        HomeAssistantTranslationCatalog(
            language: other.language,
            resources: resources.merging(other.resources) { _, new in new }
        )
    }

    private func firstValue(for keys: [String]) -> String? {
        keys.lazy.compactMap { resources[$0] }.first
    }
}
