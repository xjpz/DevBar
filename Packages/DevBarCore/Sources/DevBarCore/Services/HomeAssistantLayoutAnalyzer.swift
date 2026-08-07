import Crypto
import Foundation

public enum HomeAssistantLayoutAnalyzer {
    public static func deterministicSuggestion(for snapshot: HomeAssistantSnapshot) -> HomeAssistantLayoutSuggestion {
        let entities = presentedEntities(in: snapshot)
        let featured = entities
            .filter { ["light", "climate", "cover", "lock"].contains($0.domain) && $0.isAvailable }
            .prefix(6)
            .map(\.entityID)
        let activeLights = entities.filter { $0.domain == "light" && $0.isOn }.count
        let suggestions = activeLights > 2 ? ["当前有 \(activeLights) 盏灯开启，可考虑创建一键关闭场景"] : []
        return HomeAssistantLayoutSuggestion(
            roomOrder: snapshot.rooms.map(\.id),
            featuredEntityIDs: Array(featured),
            suggestions: suggestions
        )
    }

    public static func prompt(for snapshot: HomeAssistantSnapshot) throws -> String {
        let visibleEntities = presentedEntities(in: snapshot)
        let payload = AnalysisPayload(
            version: 1,
            rooms: snapshot.rooms.map { .init(id: $0.id, name: $0.name) },
            entities: visibleEntities.map {
                .init(
                    id: $0.entityID,
                    name: $0.name,
                    roomID: $0.areaID,
                    domain: $0.domain,
                    deviceClass: $0.deviceClass,
                    capabilities: $0.availableServices.sorted()
                )
            }
        )
        let data = try JSONEncoder().encode(payload)
        guard let json = String(data: data, encoding: .utf8) else { throw HomeAssistantError.invalidResponse }
        return """
        你是智能家居控制台的信息架构助手。只做展示建议，不生成服务调用或控制参数。
        根据以下脱敏 Home Assistant 拓扑返回纯 JSON，不要 Markdown：
        {"roomOrder":["room-id"],"featuredEntityIDs":["entity.id"],"aliases":{"entity.id":"友好别名"},"suggestions":["简短建议"]}
        只能引用输入中已有 ID；最多 6 个重点实体、4 条建议；不要猜测或修改真实房间归属。
        输入：\(json)
        """
    }

    public static func validatedSuggestion(
        from response: String,
        snapshot: HomeAssistantSnapshot
    ) throws -> HomeAssistantLayoutSuggestion {
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(HomeAssistantLayoutSuggestion.self, from: data) else {
            throw HomeAssistantError.invalidResponse
        }
        let roomIDs = Set(snapshot.rooms.map(\.id))
        let entityIDs = Set(presentedEntities(in: snapshot).map(\.entityID))
        let roomOrder = unique(decoded.roomOrder.filter(roomIDs.contains))
        let featured = Array(unique(decoded.featuredEntityIDs.filter(entityIDs.contains)).prefix(6))
        let aliases = decoded.aliases.reduce(into: [String: String]()) { result, pair in
            let alias = pair.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if entityIDs.contains(pair.key), !alias.isEmpty, alias.count <= 40 { result[pair.key] = alias }
        }
        let suggestions = Array(decoded.suggestions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 100 }
            .prefix(4))
        return HomeAssistantLayoutSuggestion(
            roomOrder: roomOrder,
            featuredEntityIDs: featured,
            aliases: aliases,
            suggestions: suggestions
        )
    }

    public static func topologyHash(for snapshot: HomeAssistantSnapshot) -> String {
        let input = presentedEntities(in: snapshot)
            .map { "\($0.entityID)|\($0.areaID ?? "")|\($0.domain)" }
            .sorted()
            .joined(separator: "\n")
        return SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func presentedEntities(in snapshot: HomeAssistantSnapshot) -> [HomeAssistantEntity] {
        let entities = snapshot.cards.flatMap(\.entities)
        var seen = Set<String>()
        return entities.filter { seen.insert($0.entityID).inserted }
    }
}

private struct AnalysisPayload: Encodable {
    struct Room: Encodable { let id: String; let name: String }
    struct Entity: Encodable {
        let id: String
        let name: String
        let roomID: String?
        let domain: String
        let deviceClass: String?
        let capabilities: [String]
    }
    let version: Int
    let rooms: [Room]
    let entities: [Entity]
}
