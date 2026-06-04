import Intents
import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?
    private var downloadTask: URLSessionDataTask?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        bestAttemptContent = content

        guard let rawURL = content.userInfo["icon-url"] as? String,
              let url = URL(string: rawURL),
              url.scheme?.lowercased() == "https"
        else {
            contentHandler(content)
            return
        }

        downloadTask = URLSession.shared.dataTask(with: url) { [weak self] data, response, _ in
            guard let self, let data,
                  data.count <= 1_000_000,
                  let response = response as? HTTPURLResponse,
                  200..<300 ~= response.statusCode
            else {
                self?.finish()
                return
            }

            self.addCommunicationAvatar(data, to: content)
            self.addAttachment(data, to: content)
            self.finish()
        }
        downloadTask?.resume()
    }

    override func serviceExtensionTimeWillExpire() {
        downloadTask?.cancel()
        finish()
    }

    private func addCommunicationAvatar(_ data: Data, to content: UNMutableNotificationContent) {
        let sender = INPerson(
            personHandle: INPersonHandle(value: "agent-watcher", type: .unknown),
            nameComponents: nil,
            displayName: "Agent Watcher",
            image: INImage(imageData: data),
            contactIdentifier: nil,
            customIdentifier: "agent-watcher"
        )
        let intent = INSendMessageIntent(
            recipients: nil,
            outgoingMessageType: .outgoingMessageText,
            content: content.body,
            speakableGroupName: nil,
            conversationIdentifier: "agent-watcher",
            serviceName: "DevBar",
            sender: sender,
            attachments: nil
        )
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        interaction.donate(completion: nil)
        if let updated = try? content.updating(from: intent) {
            bestAttemptContent = updated.mutableCopy() as? UNMutableNotificationContent
        }
    }

    private func addAttachment(_ data: Data, to content: UNMutableNotificationContent) {
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("agent-watcher-\(UUID().uuidString).png")
        guard (try? data.write(to: fileURL, options: .atomic)) != nil,
              let attachment = try? UNNotificationAttachment(identifier: "agent-watcher-icon", url: fileURL)
        else { return }
        bestAttemptContent?.attachments = [attachment]
    }

    private func finish() {
        guard let contentHandler, let content = bestAttemptContent else { return }
        self.contentHandler = nil
        contentHandler(content)
    }
}
