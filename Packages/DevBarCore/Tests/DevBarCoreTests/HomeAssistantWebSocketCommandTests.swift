import Foundation
import Testing
@testable import DevBarCore

@Suite("Home Assistant WebSocket commands")
struct HomeAssistantWebSocketCommandTests {
    @Test("Command queue preserves assigned identifier order")
    func commandQueuePreservesIdentifierOrder() {
        var queue = HomeAssistantWebSocketCommandQueue()
        for id in 12...16 {
            queue.enqueue(.init(
                id: id,
                operation: "operation-\(id)",
                text: "{\"id\":\(id)}",
                epoch: 4
            ))
        }

        var sentIDs: [Int] = []
        while let command = queue.next(for: 4) {
            sentIDs.append(command.id)
        }

        #expect(sentIDs == [12, 13, 14, 15, 16])
        #expect(queue.isEmpty)
    }

    @Test("Command queue discards commands from a stale connection")
    func commandQueueRejectsStaleConnectionEpoch() throws {
        var queue = HomeAssistantWebSocketCommandQueue()
        queue.enqueue(.init(id: 21, operation: "old", text: "old", epoch: 7))
        queue.enqueue(.init(id: 22, operation: "current", text: "current", epoch: 8))

        let currentValue = queue.next(for: 8)
        let current = try #require(currentValue)

        #expect(current.id == 22)
        #expect(current.epoch == 8)
        #expect(queue.next(for: 8) == nil)
    }

    @Test("A consumed failed send does not block the next command")
    func failedSendDoesNotBlockFollowingCommand() throws {
        var queue = HomeAssistantWebSocketCommandQueue()
        queue.enqueue(.init(id: 31, operation: "first", text: "first", epoch: 9))
        queue.enqueue(.init(id: 32, operation: "second", text: "second", epoch: 9))

        let failedValue = queue.next(for: 9)
        let followingValue = queue.next(for: 9)
        let failed = try #require(failedValue)
        let following = try #require(followingValue)

        #expect(failed.id == 31)
        #expect(following.id == 32)
        #expect(queue.isEmpty)
    }

    @Test("Service calls place the entity target in service_data")
    func serviceCallUsesCompatibleEntityIDPayload() throws {
        let call = HomeAssistantServiceCall(
            domain: "light",
            service: "turn_on",
            targetEntityID: "light.living_room",
            data: ["brightness_pct": .number(60)],
            requiresConfirmation: false
        )

        let payload = HomeAssistantWebSocketCommandAdapter.serviceCallPayload(call)
        let serviceData = try #require(payload["service_data"]?.objectValue)

        #expect(payload["domain"] == .string("light"))
        #expect(payload["service"] == .string("turn_on"))
        #expect(payload["target"] == nil)
        #expect(serviceData["entity_id"] == .string("light.living_room"))
        #expect(serviceData["brightness_pct"] == .number(60))
    }

    @Test("Failed commands preserve Home Assistant's reason")
    func commandFailurePreservesProviderMessage() {
        let error = HomeAssistantWebSocketCommandAdapter.commandError(from: .object([
            "code": .string("home_assistant_error"),
            "message": .string("Service light.turn_on failed"),
        ]))

        #expect(error == .commandFailed(
            "Service light.turn_on failed（home_assistant_error）"
        ))
        #expect(error.localizedDescription.contains("Service light.turn_on failed"))
    }

    @Test("Failed commands have a useful fallback reason")
    func commandFailureWithoutDetailsUsesFallback() {
        let error = HomeAssistantWebSocketCommandAdapter.commandError(from: .object([:]))

        #expect(error == .commandFailed("Home Assistant 未提供失败原因"))
        #expect(error.localizedDescription != "Home Assistant 返回了无法识别的数据")
    }
}
