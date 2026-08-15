import Foundation
import Testing
@testable import DevBarCore

@Suite("Home Assistant WebSocket commands")
struct HomeAssistantWebSocketCommandTests {
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
