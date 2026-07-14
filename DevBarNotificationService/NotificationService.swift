import Intents
import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNNotificationContent?
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

            self.applyCommunicationAvatar(data, to: content)
        }
        downloadTask?.resume()
    }

    override func serviceExtensionTimeWillExpire() {
        downloadTask?.cancel()
        finish()
    }

    private func applyCommunicationAvatar(_ data: Data, to content: UNMutableNotificationContent) {
        let senderIdentifier = (content.userInfo["notificationType"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "devbar-notification"
        let senderDisplayName = content.title.isEmpty ? "DevBar" : content.title
        let sender = INPerson(
            personHandle: INPersonHandle(value: senderIdentifier, type: .unknown),
            nameComponents: nil,
            displayName: senderDisplayName,
            image: INImage(imageData: data),
            contactIdentifier: nil,
            customIdentifier: senderIdentifier
        )
        let intent = INSendMessageIntent(
            recipients: nil,
            outgoingMessageType: .outgoingMessageText,
            content: content.body,
            speakableGroupName: nil,
            conversationIdentifier: senderIdentifier,
            serviceName: "DevBar",
            sender: sender,
            attachments: nil
        )
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        interaction.donate { [weak self] error in
            guard let self else { return }
            if error == nil, let updatedContent = try? content.updating(from: intent) {
                self.bestAttemptContent = updatedContent
            }
            self.finish()
        }
    }

    private func finish() {
        guard let contentHandler, let content = bestAttemptContent else { return }
        self.contentHandler = nil
        contentHandler(content)
    }
}
