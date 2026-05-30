import SwiftUI

struct IOSToolCopyButton: View {
    @Environment(\.themeTokens) private var theme

    let isCopied: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Label("ios_tools_qr_copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .foregroundStyle(isCopied ? theme.success : theme.brandPrimary)
        .disabled(isCopied)
        .animation(.easeOut(duration: 0.25), value: isCopied)
    }
}
