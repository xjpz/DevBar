import DevBarCore
import Combine
import Foundation

enum IOSAccountDeviceLinkState: Equatable {
    case notRequired
    case linking
    case linked
    case conflict
    case unavailable
}

@MainActor
final class IOSAccountViewModel: ObservableObject {
    @Published private(set) var profile: DevBarUserProfile?
    @Published private(set) var messages: [DevBarMessage] = []
    @Published private(set) var unreadCount = 0
    @Published private(set) var isWorking = false
    @Published private(set) var deviceLinkState: IOSAccountDeviceLinkState = .notRequired
    @Published private(set) var deviceLinkMessage: String?
    @Published var errorMessage: String?

    private let api: DevBarAccountAPIClient
    private let sessionStore: any DevBarSessionStoring
    private let profileCache: DevBarProfileCacheStore
    private let relayStore: DeviceRelayStore
    private var sessionToken: String?
    private var didRestore = false
    private var cancellables = Set<AnyCancellable>()

    init(
        api: DevBarAccountAPIClient = DevBarAccountAPIClient(),
        sessionStore: any DevBarSessionStoring = KeychainDevBarSessionStore(),
        profileCache: DevBarProfileCacheStore = DevBarProfileCacheStore(),
        relayStore: DeviceRelayStore = DeviceRelayStore()
    ) {
        self.api = api
        self.sessionStore = sessionStore
        self.profileCache = profileCache
        self.relayStore = relayStore
        sessionToken = sessionStore.loadToken()
        if sessionToken != nil { profile = profileCache.loadActive() }
        NotificationCenter.default.publisher(for: .iosDevBarMessageNotificationOpened)
            .compactMap { $0.userInfo?["messageId"] as? String }
            .sink { [weak self] messageId in
                Task { @MainActor [weak self] in
                    await self?.markNotificationMessageRead(messageId: messageId)
                }
            }
            .store(in: &cancellables)
    }

    var isAuthenticated: Bool { sessionToken != nil }

    func restoreSession() async {
        guard !didRestore else { return }
        didRestore = true
        guard let token = sessionToken else { return }
        do {
            let latest = try await api.profile(token: token)
            applyProfile(latest)
            await linkCurrentDevice()
            await refreshMessages()
        } catch DevBarAccountAPIError.unauthorized(_) {
            clearLocalSession()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func completeAppleSignIn(identityToken: String, nonce: String, displayNameCandidate: String?) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let result = try await api.loginWithApple(
                identityToken: identityToken,
                nonce: nonce,
                displayNameCandidate: displayNameCandidate
            )
            guard sessionStore.saveToken(result.sessionToken) else {
                throw DevBarAccountAPIError.server(status: 0, message: "无法安全保存登录状态")
            }
            sessionToken = result.sessionToken
            applyProfile(result.profile)
            await linkCurrentDevice()
            await refreshMessages()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateDisplayName(_ displayName: String) async -> Bool {
        guard let token = sessionToken, let profile else { return false }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            applyProfile(try await api.updateProfile(
                displayName: displayName,
                profileVersion: profile.profileVersion,
                token: token
            ))
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func logout() async {
        guard let token = sessionToken else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await api.logout(token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
        clearLocalSession()
    }

    func deleteAccount() async -> Bool {
        guard let token = sessionToken, !isWorking else { return false }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await api.deleteAccount(token: token)
            profileCache.deleteActiveProfile()
            clearLocalSession()
            return true
        } catch DevBarAccountAPIError.unauthorized(let message) {
            clearLocalSession()
            errorMessage = message
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func refreshMessages(filter: DevBarMessageFilter = .all) async {
        guard let token = sessionToken else {
            messages = []
            unreadCount = 0
            return
        }
        do {
            async let pageRequest = api.messages(filter: filter, token: token)
            async let count = api.unreadCount(token: token)
            let page = try await pageRequest
            messages = page.items
            unreadCount = try await count
        } catch DevBarAccountAPIError.unauthorized(_) {
            clearLocalSession()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func retryDeviceLink() async {
        guard sessionToken != nil else { return }
        await linkCurrentDevice()
        if deviceLinkState == .linked {
            await refreshMessages()
        }
    }

    func setRead(_ message: DevBarMessage, isRead: Bool) async {
        guard let token = sessionToken else { return }
        do {
            try await api.setMessageRead(message.id, isRead: isRead, token: token)
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages[index].isRead = isRead
            }
            unreadCount = max(0, unreadCount + (isRead ? -1 : 1))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markAllRead() async {
        guard let token = sessionToken else { return }
        do {
            try await api.markAllRead(token: token)
            messages = messages.map { item in
                var updated = item
                updated.isRead = true
                return updated
            }
            unreadCount = 0
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ message: DevBarMessage) async {
        guard let token = sessionToken else { return }
        do {
            try await api.deleteMessage(message.id, token: token)
            messages.removeAll { $0.id == message.id }
            if !message.isRead { unreadCount = max(0, unreadCount - 1) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyProfile(_ value: DevBarUserProfile) {
        profile = value
        profileCache.save(value)
    }

    private func clearLocalSession() {
        sessionStore.clearToken()
        profileCache.clearActiveUser()
        sessionToken = nil
        profile = nil
        messages = []
        unreadCount = 0
        deviceLinkState = .notRequired
        deviceLinkMessage = nil
    }

    private func linkCurrentDevice() async {
        guard let appToken = sessionToken else {
            deviceLinkState = .notRequired
            deviceLinkMessage = nil
            return
        }
        guard let deviceToken = relayStore.loadDeviceToken(for: .iPhone) else {
            deviceLinkState = .unavailable
            deviceLinkMessage = "当前 iPhone 尚未完成设备注册，请稍后重试"
            return
        }

        deviceLinkState = .linking
        deviceLinkMessage = nil
        do {
            let deviceSecret = try relayStore.loadOrCreateDeviceSecret(for: .iPhone)
            _ = try await api.linkCurrentDevice(
                appToken: appToken,
                deviceToken: deviceToken,
                deviceSecret: deviceSecret
            )
            deviceLinkState = .linked
        } catch DevBarAccountAPIError.conflict(let message) {
            deviceLinkState = .conflict
            deviceLinkMessage = message
        } catch {
            deviceLinkState = .unavailable
            deviceLinkMessage = error.localizedDescription
        }
    }

    private func markNotificationMessageRead(messageId: String) async {
        guard let token = sessionToken else { return }
        do {
            try await api.markMessageRead(messageId: messageId, token: token)
            if let index = messages.firstIndex(where: { $0.messageId == messageId }) {
                let wasUnread = !messages[index].isRead
                messages[index].isRead = true
                if wasUnread { unreadCount = max(0, unreadCount - 1) }
            } else {
                await refreshMessages()
            }
        } catch DevBarAccountAPIError.unauthorized(_) {
            clearLocalSession()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
