import DevBarCore
import Foundation
import UIKit
import UserNotifications

@MainActor
struct IOSSMSAlertRelayService {
    enum Result: Equatable {
        case relayForwarded(macName: String)
        case apnsFallback(macName: String)
        case duplicate
        case emptyMessage
        case unpaired
        case pushUnavailable(macName: String)
        case failed(String)

        var dialogText: String {
            switch self {
            case .relayForwarded(let macName):
                return "已通过 Relay 转发短信提醒到 \(macName)。"
            case .apnsFallback(let macName):
                return "\(macName) 当前不在线，已通过系统通知推送。"
            case .duplicate:
                return "5 分钟内已转发过相同短信，已跳过重复提醒。"
            case .emptyMessage:
                return "没有收到短信内容，请检查快捷指令变量。"
            case .unpaired:
                return "请先在 DevBar 的 Mac Relay 中绑定 Mac。"
            case .pushUnavailable(let macName):
                return "\(macName) 当前离线，且没有可用的 Mac 系统通知 token。"
            case .failed(let message):
                return "DevBar 转发短信提醒失败：\(message)"
            }
        }
    }

    private let center = UNUserNotificationCenter.current()

    func forward(
        messageText: String,
        sender: String?,
        matchedKeyword: String?,
        notificationTitle: String?,
        selectedMac: MacDeviceEntity?
    ) async -> Result {
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            return .emptyMessage
        }

        let receivedAt = Int64(Date().timeIntervalSince1970 * 1000)
        let dedupKey = DeviceRelaySMSAlert.dedupKey(
            sender: sender,
            messageText: trimmedMessage,
            receivedAt: receivedAt
        )
        guard !Self.isRecentlyForwarded(dedupKey: dedupKey, now: Date()) else {
            return .duplicate
        }

        await sendLocalNotification(
            title: iPhoneNotificationTitle(sender: sender),
            body: DeviceRelaySMSAlert.summary(for: trimmedMessage)
        )

        let manager = DeviceRelayManager()
        defer { manager.stop() }

        await manager.resumeConnectivity(
            deviceType: .iPhone,
            deviceName: UIDevice.current.name
        )

        let targetMac: MacDeviceEntity?
        if let selectedMac {
            targetMac = selectedMac
        } else {
            let localMac = manager.peers
                .filter { $0.deviceType == .mac }
                .map(MacDeviceEntity.init(device:))
                .first
            if let localMac {
                targetMac = localMac
            } else {
                targetMac = await MacDeviceEntityQuery.defaultResult()
            }
        }

        guard let targetMac else {
            return .unpaired
        }
        guard let relayDeviceToken = manager.deviceToken, !relayDeviceToken.isEmpty else {
            return .failed("设备尚未注册")
        }

        do {
            let response = try await PushNotificationService.shared.sendSMSAlert(
                SMSAlertRequest(
                    targetDeviceId: targetMac.id,
                    messageText: trimmedMessage,
                    sender: normalized(sender),
                    matchedKeyword: normalized(matchedKeyword),
                    notificationTitle: normalized(notificationTitle),
                    receivedAt: receivedAt,
                    dedupKey: dedupKey,
                    fallbackNotification: true
                ),
                deviceToken: relayDeviceToken
            )
            Self.recordForwarded(dedupKey: dedupKey, now: Date())
            switch response.delivery {
            case .relayForwarded:
                return .relayForwarded(macName: targetMac.name)
            case .apnsFallback:
                return .apnsFallback(macName: targetMac.name)
            case .duplicate:
                return .duplicate
            case .pushUnavailable, .targetMissing, .targetOffline:
                return .pushUnavailable(macName: targetMac.name)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func sendLocalNotification(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "sms-alert-\(UUID().uuidString.lowercased())",
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
        } catch {
            print("[DevBar:iOS:SMSAlert] notification failed: \(error)")
        }
    }

    private func iPhoneNotificationTitle(sender: String?) -> String {
        guard let sender = sender?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sender.isEmpty else {
            return "DevBar 已转发短信提醒"
        }
        return "DevBar 已转发短信提醒 · \(sender)"
    }

    private func normalized(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private static func isRecentlyForwarded(dedupKey: String, now: Date) -> Bool {
        let cache = loadDedupCache(now: now)
        guard let lastSeen = cache[dedupKey] else { return false }
        return now.timeIntervalSince1970 - lastSeen < 300
    }

    private static func recordForwarded(dedupKey: String, now: Date) {
        var cache = loadDedupCache(now: now)
        cache[dedupKey] = now.timeIntervalSince1970
        UserDefaults.standard.set(cache, forKey: dedupCacheKey)
    }

    private static func loadDedupCache(now: Date) -> [String: TimeInterval] {
        let raw = UserDefaults.standard.dictionary(forKey: dedupCacheKey) as? [String: TimeInterval] ?? [:]
        return raw.filter { now.timeIntervalSince1970 - $0.value < 300 }
    }

    private static let dedupCacheKey = "ios_sms_alert_relay_dedup_cache"
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
