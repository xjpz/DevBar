import DevBarCore
import SwiftUI

struct IOSHomeAssistantRoomPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeTokens) private var theme
    let rooms: [HomeAssistantRoom]
    @Binding var selectedAreaID: String

    var body: some View {
        List {
            Section {
                ForEach(rooms) { room in
                    roomButton(room)
                }
            }

            Section {
                roomButton(HomeAssistantRoom(
                    id: HomeAssistantTopologyBuilder.unassignedAreaID,
                    name: "不显示在家庭中"
                ))
            } footer: {
                Text("未选择房间的设备不会显示在家庭主页，可稍后从“待整理的设备”中重新分配。")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background((theme.isGeek ? Color.black : theme.backgroundSecondary).ignoresSafeArea())
        .navigationTitle("房间")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func roomButton(_ room: HomeAssistantRoom) -> some View {
        Button {
            selectedAreaID = room.id
            dismiss()
        } label: {
            HStack {
                Text(room.name)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                if selectedAreaID == room.id {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(theme.warning)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
