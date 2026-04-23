// NotificationService.swift
// DevBar

import Foundation
import Combine
import UserNotifications
import AppKit
import DevBarCore

struct NotificationQuotaItem {
    let key: String
    let name: String
    let percentage: Int
}

@MainActor
final class NotificationService: ObservableObject {
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let center = UNUserNotificationCenter.current()

    init() {
        Task {
            await checkAuthorizationStatus()
        }
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            await checkAuthorizationStatus()
            return granted
        } catch {
            print("[DevBar] Notification authorization error: \(error)")
            return false
        }
    }

    private func checkAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func openSystemNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Send Notification

    func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error = error {
                print("[DevBar] Notification send error: \(error)")
            }
        }
    }

    // MARK: - Check and Notify

    func checkAndNotify(provider: QuotaProvider, items: [NotificationQuotaItem], settings: NotificationSettings, previousItems: [NotificationQuotaItem]?) {
        Task {
            await checkLowQuota(provider: provider, items: items, settings: settings)
            await checkExhausted(provider: provider, items: items, settings: settings)
            await checkReset(provider: provider, items: items, previousItems: previousItems, settings: settings)
        }
    }

    private func checkLowQuota(provider: QuotaProvider, items: [NotificationQuotaItem], settings: NotificationSettings) async {
        let threshold = settings.lowQuotaThreshold
        let currentLowItems = items.filter { Double($0.percentage) >= (100 - threshold) }
        let currentLowKeys = Set(currentLowItems.map(\.key))
        let previousLowKeys = loadNotificationState(for: provider, baseKey: Constants.Defaults.lowQuotaActiveItemsKey)
        let newlyLowItems = currentLowItems.filter { !previousLowKeys.contains($0.key) }

        if settings.lowQuotaEnabled,
           authorizationStatus == .authorized,
           !newlyLowItems.isEmpty {
            let typesStr = newlyLowItems.map(\.name).joined(separator: "、")
            send(
                title: notificationTitle(baseKey: "notif_low_quota_title", provider: provider),
                body: String(format: String(localized: "notif_low_quota_body"), typesStr, Int(threshold))
            )
        }

        saveNotificationState(currentLowKeys, for: provider, baseKey: Constants.Defaults.lowQuotaActiveItemsKey)
    }

    private func checkExhausted(provider: QuotaProvider, items: [NotificationQuotaItem], settings: NotificationSettings) async {
        let currentExhaustedItems = items.filter { $0.percentage >= 100 }
        let currentExhaustedKeys = Set(currentExhaustedItems.map(\.key))
        let previousExhaustedKeys = loadNotificationState(for: provider, baseKey: Constants.Defaults.exhaustedActiveItemsKey)
        let newlyExhaustedItems = currentExhaustedItems.filter { !previousExhaustedKeys.contains($0.key) }

        if settings.exhaustedEnabled,
           authorizationStatus == .authorized,
           !newlyExhaustedItems.isEmpty {
            let typesStr = newlyExhaustedItems.map(\.name).joined(separator: "、")
            send(
                title: notificationTitle(baseKey: "notif_exhausted_title", provider: provider),
                body: String(format: String(localized: "notif_exhausted_body"), typesStr)
            )
        }

        saveNotificationState(currentExhaustedKeys, for: provider, baseKey: Constants.Defaults.exhaustedActiveItemsKey)
    }

    private func checkReset(provider: QuotaProvider, items: [NotificationQuotaItem], previousItems: [NotificationQuotaItem]?, settings: NotificationSettings) async {
        guard settings.resetEnabled,
              authorizationStatus == .authorized,
              let previousItems else { return }

        var resetTypes: [String] = []

        let previousDict = Dictionary(uniqueKeysWithValues: previousItems.map { ($0.key, $0) })

        for current in items {
            if let previous = previousDict[current.key] {
                if hasReset(current: current, previous: previous) {
                    resetTypes.append(current.name)
                }
            }
        }

        if !resetTypes.isEmpty {
            let typesStr = resetTypes.joined(separator: "、")
            send(
                title: notificationTitle(baseKey: "notif_reset_title", provider: provider),
                body: String(format: String(localized: "notif_reset_body"), typesStr)
            )
            recordResetNotificationTime(for: provider)
        }
    }

    private func hasReset(current: NotificationQuotaItem, previous: NotificationQuotaItem) -> Bool {
        // Reset detected if:
        // 1. Previous was exhausted (percentage >= 100)
        // 2. Current has lower percentage than previous (meaning reset happened)
        guard previous.percentage >= 100 else { return false }
        return current.percentage < previous.percentage
    }

    private func notificationKey(_ baseKey: String, provider: QuotaProvider) -> String {
        "\(baseKey)_\(provider.rawValue)"
    }

    private func notificationTitle(baseKey: String, provider: QuotaProvider) -> String {
        let localizedTitle = Bundle.main.localizedString(forKey: baseKey, value: baseKey, table: nil)
        return "\(localizedTitle) · \(provider.localizedName)"
    }

    private func recordLowQuotaNotificationTime(for provider: QuotaProvider) {
        UserDefaults.standard.set(
            Date().timeIntervalSince1970,
            forKey: notificationKey(Constants.Defaults.lastLowQuotaNotificationTimeKey, provider: provider)
        )
    }

    private func recordExhaustedNotificationTime(for provider: QuotaProvider) {
        UserDefaults.standard.set(
            Date().timeIntervalSince1970,
            forKey: notificationKey(Constants.Defaults.lastExhaustedNotificationTimeKey, provider: provider)
        )
    }

    private func recordResetNotificationTime(for provider: QuotaProvider) {
        UserDefaults.standard.set(
            Date().timeIntervalSince1970,
            forKey: notificationKey(Constants.Defaults.lastResetNotificationTimeKey, provider: provider)
        )
    }

    private func loadNotificationState(for provider: QuotaProvider, baseKey: String) -> Set<String> {
        let values = UserDefaults.standard.stringArray(forKey: notificationKey(baseKey, provider: provider)) ?? []
        return Set(values)
    }

    private func saveNotificationState(_ state: Set<String>, for provider: QuotaProvider, baseKey: String) {
        UserDefaults.standard.set(Array(state).sorted(), forKey: notificationKey(baseKey, provider: provider))
    }
}
