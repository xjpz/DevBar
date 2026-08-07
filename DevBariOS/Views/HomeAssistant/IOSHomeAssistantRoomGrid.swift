import DevBarCore
import SwiftUI
import UniformTypeIdentifiers

struct IOSHomeAssistantRoomGrid: View {
    let accessories: [HomeAssistantAccessory]
    let pendingEntityIDs: Set<String>
    let controlsEnabled: Bool
    let isEditing: Bool
    let theme: IOSThemeTokens
    @Binding var draggedAccessoryID: String?
    let roomID: String
    let size: (HomeAssistantAccessory) -> HomeAssistantCardSize
    let semanticState: (HomeAssistantAccessory) -> HomeAssistantAccessorySemanticState
    let open: (HomeAssistantAccessory) -> Void
    let edit: (HomeAssistantAccessory) -> Void
    let quickAction: (HomeAssistantAccessory) -> Void
    let toggleSize: (String) -> Void
    let hide: (String) -> Void
    let beginLayoutEditing: (() -> Void)?
    let move: (String, String, String) -> Void

    var body: some View {
        let columns = masonryColumns
        HStack(alignment: .top, spacing: IOSHomeAssistantCardMetrics.spacing) {
            ForEach(0..<2, id: \.self) { column in
                LazyVStack(spacing: IOSHomeAssistantCardMetrics.spacing) {
                    ForEach(columns[column]) { accessory in
                        card(accessory)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: layoutSignature)
    }

    @ViewBuilder
    private func card(_ accessory: HomeAssistantAccessory) -> some View {
        let card = IOSHomeAssistantDeviceCard(
            accessory: accessory,
            state: semanticState(accessory),
            size: size(accessory),
            isPending: accessory.quickControlEntity.map {
                pendingEntityIDs.contains($0.entityID)
            } ?? false,
            controlsEnabled: controlsEnabled,
            isEditing: isEditing,
            theme: theme,
            open: { open(accessory) },
            edit: { edit(accessory) },
            quickAction: { quickAction(accessory) },
            toggleSize: { toggleSize(accessory.id) },
            hide: { hide(accessory.id) },
            beginLayoutEditing: beginLayoutEditing
        )
        .scaleEffect(draggedAccessoryID == accessory.id ? 0.96 : 1)
        .opacity(draggedAccessoryID == accessory.id ? 0.72 : 1)

        if isEditing {
            card
                .onDrag {
                    draggedAccessoryID = accessory.id
                    return NSItemProvider(object: accessory.id as NSString)
                }
                .onDrop(
                    of: [UTType.plainText],
                    delegate: IOSHomeAssistantAccessoryDropDelegate(
                        targetID: accessory.id,
                        roomID: roomID,
                        draggedAccessoryID: $draggedAccessoryID,
                        move: move
                    )
                )
        } else {
            card
        }
    }

    private var masonryColumns: [[HomeAssistantAccessory]] {
        var columns = [[HomeAssistantAccessory](), [HomeAssistantAccessory]()]
        var heights = [CGFloat.zero, CGFloat.zero]
        for accessory in accessories {
            let column = heights[0] <= heights[1] ? 0 : 1
            columns[column].append(accessory)
            heights[column] += size(accessory).dashboardHeight + IOSHomeAssistantCardMetrics.spacing
        }
        return columns
    }

    private var layoutSignature: [String] {
        accessories.map { "\($0.id):\(size($0).rawValue)" }
    }
}

private struct IOSHomeAssistantAccessoryDropDelegate: DropDelegate {
    let targetID: String
    let roomID: String
    @Binding var draggedAccessoryID: String?
    let move: (String, String, String) -> Void

    func dropEntered(info _: DropInfo) {
        guard let draggedAccessoryID, draggedAccessoryID != targetID else { return }
        move(draggedAccessoryID, targetID, roomID)
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info _: DropInfo) -> Bool {
        draggedAccessoryID = nil
        return true
    }

    func dropExited(info _: DropInfo) {}
}
