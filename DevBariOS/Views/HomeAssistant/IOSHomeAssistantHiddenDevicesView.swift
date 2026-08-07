import DevBarCore
import SwiftUI

struct IOSHomeAssistantHiddenDevicesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeTokens) private var theme
    @ObservedObject var model: IOSHomeAssistantViewModel

    var body: some View {
        Group {
            if groups.isEmpty {
                ContentUnavailableView(
                    "没有隐藏的设备",
                    systemImage: "eye",
                    description: Text("长按设备卡片或在设备详情中可以隐藏设备。")
                )
            } else {
                List {
                    ForEach(groups) { group in
                        Section(group.name) {
                            ForEach(group.accessories) { accessory in
                                HStack(spacing: 12) {
                                    Image(systemName: accessory.systemImage)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(theme.textSecondary)
                                        .frame(width: 34, height: 34)
                                        .background(theme.surfaceSecondary, in: Circle())

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(accessory.name)
                                            .foregroundStyle(theme.textPrimary)
                                        Text(accessory.quickControlEntity?.entityID ?? accessory.id)
                                            .font(theme.captionFont)
                                            .foregroundStyle(theme.textTertiary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Button("显示") {
                                        model.showDevice(accessory.id)
                                    }
                                    .buttonStyle(.bordered)
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("隐藏的设备")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("完成") { dismiss() }
            }
            if !model.hiddenAccessories.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("全部显示") { model.showAllDevices() }
                }
            }
        }
        .accessibilityIdentifier("ios.homeAssistant.hiddenDevices")
    }

    private var groups: [HiddenDeviceGroup] {
        Dictionary(grouping: model.hiddenAccessories) {
            $0.areaID ?? HomeAssistantTopologyBuilder.unassignedAreaID
        }
            .map { key, accessories in
                HiddenDeviceGroup(
                    id: key,
                    name: model.roomName(for: accessories[0]),
                    accessories: accessories
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

private struct HiddenDeviceGroup: Identifiable {
    let id: String
    let name: String
    let accessories: [HomeAssistantAccessory]
}
