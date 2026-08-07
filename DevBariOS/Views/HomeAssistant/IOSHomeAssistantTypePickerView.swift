import DevBarCore
import SwiftUI

struct IOSHomeAssistantTypePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeTokens) private var theme
    @Binding var kind: HomeAssistantAccessoryKind
    @Binding var selectedSystemImage: String

    private let editableKinds: [HomeAssistantAccessoryKind] = [
        .switchDevice, .light, .fan, .airPurifier, .airConditioner,
    ]

    var body: some View {
        List(editableKinds) { type in
            Button {
                if kind != type {
                    kind = type
                    selectedSystemImage = type.systemImage
                }
                dismiss()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: type.systemImage)
                        .font(.system(size: 22, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(theme.warning)
                        .frame(width: 46, height: 46)
                        .background(theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                    Text(type.displayName)
                        .font(theme.appFont.font(.body, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)

                    Spacer()

                    if kind == type {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.bold))
                            .foregroundStyle(theme.warning)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background((theme.isGeek ? Color.black : theme.backgroundSecondary).ignoresSafeArea())
        .navigationTitle("设备类型")
        .navigationBarTitleDisplayMode(.inline)
    }
}
