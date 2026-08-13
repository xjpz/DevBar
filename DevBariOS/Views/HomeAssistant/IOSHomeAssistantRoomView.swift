import DevBarCore
import SwiftUI

struct IOSHomeAssistantRoomView: View {
    @Environment(\.themeTokens) private var theme
    @ObservedObject var model: IOSHomeAssistantViewModel
    let room: HomeAssistantRoom

    @State private var selectedAccessory: HomeAssistantAccessory?
    @State private var editingAccessory: HomeAssistantAccessory?
    @State private var confirmation: RoomControlConfirmation?
    @State private var draggedAccessoryID: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if !environmentItems.isEmpty {
                    environmentStrip
                }

                IOSHomeAssistantRoomGrid(
                    accessories: accessories,
                    pendingEntityIDs: model.pendingEntityIDs,
                    controlsEnabled: model.canControlDevices,
                    isEditing: false,
                    theme: theme,
                    draggedAccessoryID: $draggedAccessoryID,
                    roomID: room.id,
                    size: model.cardSize,
                    semanticState: model.semanticState,
                    open: { selectedAccessory = $0 },
                    edit: { editingAccessory = $0 },
                    quickAction: performQuickAction,
                    toggleSize: model.toggleCardSize,
                    hide: model.hideDevice,
                    beginLayoutEditing: nil,
                    move: model.moveAccessory
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background {
            IOSHomeAssistantPageBackground(theme: theme)
                .ignoresSafeArea()
        }
        .navigationTitle(room.name)
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .fullScreenCover(item: $selectedAccessory) { accessory in
            IOSHomeAssistantAccessoryControlView(model: model, accessory: accessory)
                .presentationBackground(.clear)
        }
        .sheet(item: $editingAccessory) { accessory in
            NavigationStack {
                IOSHomeAssistantDeviceEditorView(model: model, accessory: accessory)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
        .alert(item: $confirmation) { item in
            Alert(
                title: Text("确认操作"),
                message: Text("此操作可能触发门锁、场景、脚本或自动化。确定继续吗？"),
                primaryButton: .destructive(Text("继续")) {
                    Task { try? await model.execute(item.call) }
                },
                secondaryButton: .cancel()
            )
        }
        .accessibilityIdentifier("ios.homeAssistant.room.\(room.id)")
    }

    private var accessories: [HomeAssistantAccessory] {
        model.accessories(inRoom: room.id)
    }

    private var environmentItems: [RoomEnvironmentItem] {
        let entities = accessories.flatMap(\.entities)
        let temperatureValues = entities.compactMap { entity -> Double? in
            if entity.deviceClass == "temperature" { return Double(entity.state.state) }
            if entity.domain == "climate" {
                return entity.state.attributes["current_temperature"]?.doubleValue
            }
            return nil
        }
        let humidityValues = entities.compactMap { entity -> Double? in
            if entity.deviceClass == "humidity" { return Double(entity.state.state) }
            return entity.state.attributes["current_humidity"]?.doubleValue
        }

        var items: [RoomEnvironmentItem] = []
        if let value = temperatureValues.first {
            items.append(.init(title: "温度", value: String(format: "%.1f°", value), image: "thermometer.medium"))
        }
        if let value = humidityValues.first {
            items.append(.init(title: "湿度", value: "\(Int(value.rounded()))%", image: "humidity.fill"))
        }
        let activeLights = accessories.filter {
            $0.kind == .light && model.semanticState(for: $0).power == .on
        }.count
        if accessories.contains(where: { $0.kind == .light }) {
            items.append(.init(
                title: "灯",
                value: activeLights == 0 ? "全部关闭" : "\(activeLights) 盏开启",
                image: "lightbulb.fill"
            ))
        }
        return items
    }

    private var environmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(environmentItems) { item in
                    HStack(spacing: 9) {
                        Image(systemName: item.image)
                            .foregroundStyle(theme.info)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(theme.captionWeightFont)
                            Text(item.value)
                                .font(theme.captionFont)
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 56)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(theme.borderSubtle.opacity(0.7), lineWidth: 1))
                }
            }
        }
        .contentMargins(.horizontal, 0, for: .scrollContent)
    }

    private func performQuickAction(_ accessory: HomeAssistantAccessory) {
        guard let entity = accessory.quickControlEntity else { return }
        Task {
            do {
                if let call = try await model.performQuickAction(on: entity) {
                    confirmation = RoomControlConfirmation(call: call)
                }
            } catch {
                model.errorMessage = error.localizedDescription
            }
        }
    }

}

private struct RoomEnvironmentItem: Identifiable {
    let title: String
    let value: String
    let image: String
    var id: String { title }
}

private struct RoomControlConfirmation: Identifiable {
    let id = UUID()
    let call: HomeAssistantServiceCall
}
