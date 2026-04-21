// NotificationService.swift
// DevBar

import Foundation
import Combine
import UserNotifications
import AppKit

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
        guard settings.lowQuotaEnabled,
              authorizationStatus == .authorized else { return }

        guard shouldSendLowQuotaNotification(for: provider) else { return }

        let threshold = settings.lowQuotaThreshold
        var lowTypes: [String] = []

        for item in items {
            let usedPercent = Double(item.percentage)
            if usedPercent >= (100 - threshold) {
                lowTypes.append(item.name)
            }
        }

        if !lowTypes.isEmpty {
            let typesStr = lowTypes.joined(separator: "、")
            send(
                title: notificationTitle(baseKey: "notif_low_quota_title", provider: provider),
                body: String(format: String(localized: "notif_low_quota_body"), typesStr, Int(threshold))
            )
            recordLowQuotaNotificationTime(for: provider)
        }
    }

    private func checkExhausted(provider: QuotaProvider, items: [NotificationQuotaItem], settings: NotificationSettings) async {
        guard settings.exhaustedEnabled,
              authorizationStatus == .authorized else { return }

        guard shouldSendExhaustedNotification(for: provider) else { return }

        var exhaustedTypes: [String] = []

        for item in items {
            if item.percentage >= 100 {
                exhaustedTypes.append(item.name)
            }
        }

        if !exhaustedTypes.isEmpty {
            let typesStr = exhaustedTypes.joined(separator: "、")
            send(
                title: notificationTitle(baseKey: "notif_exhausted_title", provider: provider),
                body: String(format: String(localized: "notif_exhausted_body"), typesStr)
            )
            recordExhaustedNotificationTime(for: provider)
        }
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

    // MARK: - Throttling

    private func shouldSendLowQuotaNotification(for provider: QuotaProvider) -> Bool {
        let lastTime = UserDefaults.standard.double(forKey: notificationKey(Constants.Defaults.lastLowQuotaNotificationTimeKey, provider: provider))
        return Date().timeIntervalSince1970 - lastTime >= Constants.Defaults.lowQuotaNotificationInterval
    }

    private func shouldSendExhaustedNotification(for provider: QuotaProvider) -> Bool {
        let lastTime = UserDefaults.standard.double(forKey: notificationKey(Constants.Defaults.lastExhaustedNotificationTimeKey, provider: provider))
        // Exhausted notification: only once per exhaustion cycle
        // Check if current state is still exhausted
        return Date().timeIntervalSince1970 - lastTime >= Constants.Defaults.lowQuotaNotificationInterval
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
}
