import DevBarCore
import SwiftUI

struct IOSHomeAssistantPendingOrganizationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeTokens) private var theme
    @ObservedObject var model: IOSHomeAssistantViewModel

    var body: some View {
        Group {
            if model.pendingAccessories.isEmpty {
                ContentUnavailableView(
                    "没有待整理的设备",
                    systemImage: "checkmark.circle",
                    description: Text("设备类型和主要控制实体均已确认。")
                )
            } else {
                List {
                    Section {
                        ForEach(model.pendingAccessories) { accessory in
                            NavigationLink {
                                IOSHomeAssistantDeviceEditorView(model: model, accessory: accessory)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: accessory.systemImage)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(theme.warning)
                                        .frame(width: 38, height: 38)
                                        .background(theme.warning.opacity(0.12), in: Circle())

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(accessory.name)
                                            .font(theme.appFont.font(.body, weight: .semibold))
                                            .foregroundStyle(theme.textPrimary)
                                        Text("\(accessory.kind.displayName) · \(model.roomName(for: accessory)) · \(accessory.entities.count) 个实体")
                                            .font(theme.captionFont)
                                            .foregroundStyle(theme.textSecondary)
                                        Text(pendingReason(for: accessory))
                                            .font(theme.captionFont)
                                            .foregroundStyle(theme.textTertiary)
                                            .lineLimit(2)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    } footer: {
                        Text("请选择房间并确认主要控制实体。完成前设备不会出现在家庭主页，也不会执行首页快捷操作。")
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .scrollContentBackground(.hidden)
        .background((theme.isGeek ? Color.black : theme.backgroundSecondary).ignoresSafeArea())
        .navigationTitle("待整理的设备")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
        .accessibilityIdentifier("ios.homeAssistant.pendingOrganization")
    }

    private func pendingReason(for accessory: HomeAssistantAccessory) -> String {
        if accessory.areaID == nil {
            return "尚未选择房间"
        }
        return accessory.classification.reasons.joined(separator: "；")
    }
}
