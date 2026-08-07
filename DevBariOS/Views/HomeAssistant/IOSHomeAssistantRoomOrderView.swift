import DevBarCore
import SwiftUI

struct IOSHomeAssistantRoomOrderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeTokens) private var theme
    @ObservedObject var model: IOSHomeAssistantViewModel
    @State private var rooms: [HomeAssistantRoom]

    init(model: IOSHomeAssistantViewModel) {
        self.model = model
        _rooms = State(initialValue: model.rooms)
    }

    var body: some View {
        List {
            ForEach(rooms) { room in
                Text(room.name)
                    .font(theme.appFont.font(.body, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .frame(minHeight: 48)
                    .listRowBackground(theme.surfacePrimary)
            }
            .onMove(perform: moveRooms)
        }
        .environment(\.editMode, .constant(.active))
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background((theme.isGeek ? Color.black : theme.backgroundSecondary).ignoresSafeArea())
        .navigationTitle("重新排序区块")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("取消")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    model.updateRoomOrder(rooms.map(\.id))
                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                }
                .accessibilityLabel("完成")
            }
        }
        .accessibilityIdentifier("ios.homeAssistant.roomOrder")
    }

    private func moveRooms(from source: IndexSet, to destination: Int) {
        rooms.move(fromOffsets: source, toOffset: destination)
    }
}
