// NotificationService.swift
// DevBar

import Foundation
import Combine
import UserNotifications
import AppKit

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

    func checkAndNotify(
        quotaData: QuotaData,
        settings: NotificationSettings,
        previousData: QuotaData?
    ) {
        Task {
            await checkLowQuota(quotaData: quotaData, settings: settings)
            await checkExhausted(quotaData: quotaData, settings: settings)
            await checkReset(quotaData: quotaData, previousData: previousData, settings: settings)
        }
    }

    private func checkLowQuota(quotaData: QuotaData, settings: NotificationSettings) async {
        guard settings.lowQuotaEnabled,
              authorizationStatus == .authorized else { return }

        guard shouldSendLowQuotaNotification() else { return }

        let threshold = settings.lowQuotaThreshold
        var lowTypes: [String] = []

        guard let limits = quotaData.limits else { return }

        for limit in limits {
            let usedPercent = Double(limit.percentage)
            if usedPercent >= (100 - threshold) {
                lowTypes.append(limit.displayName)
            }
        }

        if !lowTypes.isEmpty {
            let typesStr = lowTypes.joined(separator: "、")
            send(
                title: String(localized: "notif_low_quota_title"),
                body: String(format: String(localized: "notif_low_quota_body"), typesStr, Int(threshold))
            )
            recordLowQuotaNotificationTime()
        }
    }

    private func checkExhausted(quotaData: QuotaData, settings: NotificationSettings) async {
        guard settings.exhaustedEnabled,
              authorizationStatus == .authorized else { return }

        guard shouldSendExhaustedNotification() else { return }

        var exhaustedTypes: [String] = []

        guard let limits = quotaData.limits else { return }

        for limit in limits {
            if limit.percentage >= 100 {
                exhaustedTypes.append(limit.displayName)
            }
        }

        if !exhaustedTypes.isEmpty {
            let typesStr = exhaustedTypes.joined(separator: "、")
            send(
                title: String(localized: "notif_exhausted_title"),
                body: String(format: String(localized: "notif_exhausted_body"), typesStr)
            )
            recordExhaustedNotificationTime()
        }
    }

    private func checkReset(quotaData: QuotaData, previousData: QuotaData?, settings: NotificationSettings) async {
        guard settings.resetEnabled,
              authorizationStatus == .authorized,
              let previous = previousData,
              let currentLimits = quotaData.limits,
              let previousLimits = previous.limits else { return }

        var resetTypes: [String] = []

        // Create a dictionary of previous limits keyed by type for quick lookup
        let previousDict = Dictionary(uniqueKeysWithValues: previousLimits.map { ($0.type, $0) })

        for current in currentLimits {
            if let previous = previousDict[current.type] {
                if hasReset(current: current, previous: previous) {
                    resetTypes.append(current.displayName)
                }
            }
        }

        if !resetTypes.isEmpty {
            let typesStr = resetTypes.joined(separator: "、")
            send(
                title: String(localized: "notif_reset_title"),
                body: String(format: String(localized: "notif_reset_body"), typesStr)
            )
            recordResetNotificationTime()
        }
    }

    private func hasReset(current: QuotaLimit, previous: QuotaLimit) -> Bool {
        // Reset detected if:
        // 1. Previous was exhausted (percentage >= 100)
        // 2. Current has lower percentage than previous (meaning reset happened)
        guard previous.percentage >= 100 else { return false }
        return current.percentage < previous.percentage
    }

    // MARK: - Throttling

    private func shouldSendLowQuotaNotification() -> Bool {
        let lastTime = UserDefaults.standard.double(
            forKey: Constants.Defaults.lastLowQuotaNotificationTimeKey
        )
        return Date().timeIntervalSince1970 - lastTime >= Constants.Defaults.lowQuotaNotificationInterval
    }

    private func shouldSendExhaustedNotification() -> Bool {
        let lastTime = UserDefaults.standard.double(
            forKey: Constants.Defaults.lastExhaustedNotificationTimeKey
        )
        // Exhausted notification: only once per exhaustion cycle
        // Check if current state is still exhausted
        return Date().timeIntervalSince1970 - lastTime >= Constants.Defaults.lowQuotaNotificationInterval
    }

    private func shouldSendResetNotification() -> Bool {
        // Reset notification: once per reset event
        return true
    }

    private func recordLowQuotaNotificationTime() {
        UserDefaults.standard.set(
            Date().timeIntervalSince1970,
            forKey: Constants.Defaults.lastLowQuotaNotificationTimeKey
        )
    }

    private func recordExhaustedNotificationTime() {
        UserDefaults.standard.set(
            Date().timeIntervalSince1970,
            forKey: Constants.Defaults.lastExhaustedNotificationTimeKey
        )
    }

    private func recordResetNotificationTime() {
        UserDefaults.standard.set(
            Date().timeIntervalSince1970,
            forKey: Constants.Defaults.lastResetNotificationTimeKey
        )
    }
}
