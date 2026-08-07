import DevBarCore
import SwiftUI
import UIKit

struct IOSHomeAssistantIconPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeTokens) private var theme
    let kind: HomeAssistantAccessoryKind
    @Binding private var selectedSystemImage: String
    @State private var draftSystemImage: String

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 18),
        count: 4
    )

    init(
        kind: HomeAssistantAccessoryKind,
        selectedSystemImage: Binding<String>
    ) {
        self.kind = kind
        _selectedSystemImage = selectedSystemImage
        _draftSystemImage = State(initialValue: selectedSystemImage.wrappedValue)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(availableSystemImages, id: \.self) { systemImage in
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) {
                            draftSystemImage = systemImage
                        }
                    } label: {
                        Image(systemName: systemImage)
                            .font(.system(size: 29, weight: .medium))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(homeAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 66)
                            .overlay {
                                if draftSystemImage == systemImage {
                                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                                        .stroke(homeAccent, lineWidth: 2)
                                }
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(systemImage)
                    .accessibilityValue(draftSystemImage == systemImage ? "已选择" : "")
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
        }
        .background((theme.isGeek ? Color.black : theme.backgroundSecondary).ignoresSafeArea())
        .navigationTitle("选取图标")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.bold))
                }
                .accessibilityLabel("取消")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    selectedSystemImage = draftSystemImage
                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                }
                .tint(homeAccent)
                .accessibilityLabel("完成")
            }
        }
        .accessibilityIdentifier("ios.homeAssistant.iconPicker")
    }

    private var availableSystemImages: [String] {
        let available = kind.systemImages.filter { UIImage(systemName: $0) != nil }
        return available.isEmpty ? [kind.systemImage] : available
    }

    private var homeAccent: Color { theme.warning }
}
