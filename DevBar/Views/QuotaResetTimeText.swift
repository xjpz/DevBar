import DevBarCore
import SwiftUI

struct QuotaResetTimeText: View {
    let exactText: String
    let resetDate: Date?

    @AppStorage(
        QuotaResetTimeDisplayMode.defaultsKey,
        store: QuotaResetTimeDisplayMode.sharedDefaults
    )
    private var displayModeRawValue = QuotaResetTimeDisplayMode.exact.rawValue

    private var displayMode: QuotaResetTimeDisplayMode {
        QuotaResetTimeDisplayMode(rawValue: displayModeRawValue) ?? .exact
    }

    var body: some View {
        Group {
            if displayMode == .countdown, let resetDate {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    resetLabel(QuotaResetTimePresentation.countdownText(until: resetDate, now: context.date))
                }
            } else {
                resetLabel(exactText)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func resetLabel(_ value: String) -> Text {
        Text(String(format: String(localized: "reset_at"), value))
    }
}
