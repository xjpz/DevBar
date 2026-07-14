import DevBarCore
import Combine
import Foundation

@MainActor
final class IOSPushOpenKeyViewModel: ObservableObject {
    @Published private(set) var keys: [PushOpenKeySummary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isCreating = false
    @Published private(set) var revokingIDs: Set<Int64> = []
    @Published var createdKey: PushOpenKeyCreated?
    @Published var errorMessage: String?

    private let service: PushNotificationService

    init(service: PushNotificationService = .shared) {
        self.service = service
    }

    func load(deviceToken: String?) async {
        guard let deviceToken, !deviceToken.isEmpty else {
            keys = []
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            keys = try await service.listOpenKeys(deviceToken: deviceToken)
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = message(for: error)
        }
    }

    func create(name: String, deviceToken: String?) async {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let deviceToken, !deviceToken.isEmpty else {
            errorMessage = "设备尚未注册，暂时无法创建 Push Key。"
            return
        }
        guard !normalizedName.isEmpty else {
            errorMessage = "请输入 Key 名称。"
            return
        }

        isCreating = true
        defer { isCreating = false }
        do {
            let created = try await service.createOpenKey(name: normalizedName, deviceToken: deviceToken)
            keys.removeAll { $0.id == created.id }
            keys.insert(created.summary, at: 0)
            createdKey = created
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = message(for: error)
        }
    }

    func revoke(_ key: PushOpenKeySummary, deviceToken: String?) async {
        guard let deviceToken, !deviceToken.isEmpty else {
            errorMessage = "设备尚未注册，暂时无法撤销 Push Key。"
            return
        }

        revokingIDs.insert(key.id)
        defer { revokingIDs.remove(key.id) }
        do {
            if try await service.revokeOpenKey(id: key.id, deviceToken: deviceToken) {
                keys.removeAll { $0.id == key.id }
            }
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = message(for: error)
        }
    }

    func clearCreatedKey() {
        createdKey = nil
    }

    private func message(for error: Error) -> String {
        switch error {
        case PushNotificationServiceError.httpError(let status):
            return "请求失败（HTTP \(status)），请稍后重试。"
        case PushNotificationServiceError.serverError(let message):
            return message
        default:
            return "网络请求失败，请检查连接后重试。"
        }
    }
}
