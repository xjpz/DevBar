import AppIntents
import DevBarCore
import Foundation

struct ForwardSMSAlertIntent: AppIntent {
    static var title: LocalizedStringResource = "转发短信提醒"
    static var description = IntentDescription("把快捷指令收到的短信内容提交到 DevBar 服务端，优先通过 Relay 转发到已配对电脑，离线时使用系统通知兜底。")

    @Parameter(title: "短信内容")
    var messageText: String

    @Parameter(title: "发送人")
    var sender: String?

    @Parameter(title: "匹配关键词")
    var matchedKeyword: String?

    @Parameter(title: "通知标题")
    var notificationTitle: String?

    @Parameter(title: "电脑")
    var mac: MacDeviceEntity?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await IOSSMSAlertRelayService().forward(
            messageText: messageText,
            sender: sender,
            matchedKeyword: matchedKeyword,
            notificationTitle: notificationTitle,
            selectedMac: mac
        )
        return .result(dialog: IntentDialog(stringLiteral: result.dialogText))
    }
}
