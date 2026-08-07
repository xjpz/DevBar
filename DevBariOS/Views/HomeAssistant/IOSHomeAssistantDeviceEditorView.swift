import DevBarCore
import SwiftUI

struct IOSHomeAssistantDeviceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeTokens) private var theme
    @ObservedObject var model: IOSHomeAssistantViewModel
    let accessory: HomeAssistantAccessory

    @State private var deviceName: String
    @State private var kind: HomeAssistantAccessoryKind
    @State private var selectedSystemImage: String
    @State private var selectedAreaID: String
    @State private var selectedPrimaryEntityID: String
    @State private var selectedPowerEntityID: String
    @State private var bindings: [HomeAssistantRoleBinding]
    @State private var splitEntityIDs: Set<String>
    @State private var expandedPicker: InlinePicker?
    @FocusState private var isNameFocused: Bool

    init(model: IOSHomeAssistantViewModel, accessory: HomeAssistantAccessory) {
        self.model = model
        self.accessory = accessory
        _deviceName = State(initialValue: accessory.name)
        _kind = State(initialValue: accessory.kind)
        _selectedSystemImage = State(initialValue: accessory.systemImage)
        _selectedAreaID = State(
            initialValue: accessory.areaID ?? HomeAssistantTopologyBuilder.unassignedAreaID
        )
        _selectedPrimaryEntityID = State(initialValue: accessory.primaryControlEntity?.entityID ?? "")
        _selectedPowerEntityID = State(initialValue: accessory.powerEntity?.entityID ?? "")
        _bindings = State(initialValue: accessory.bindings)
        _splitEntityIDs = State(
            initialValue: model.accessoryGrouping.splitEntityIDs(for: accessory.sourceCardID)
        )
    }

    var body: some View {
        Form {
            Section {
                nameAndIconEditor
                    .listRowInsets(EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))
            }

            Section {
                Button {
                    togglePicker(.room)
                } label: {
                    settingsRow(title: "房间", value: selectedRoomName)
                }
                .buttonStyle(.plain)

                if expandedPicker == .room {
                    roomPicker
                }

                Button {
                    togglePicker(.displayType)
                } label: {
                    settingsRow(title: "显示为", value: kind.displayName)
                }
                .buttonStyle(.plain)

                if expandedPicker == .displayType {
                    displayTypePicker
                }
            }

            if accessory.isSplitAccessory || splitCandidates.count > 1 {
                Section {
                    if accessory.isSplitAccessory {
                        Button {
                            model.mergeAccessory(accessory)
                            dismiss()
                        } label: {
                            Text("合并回“\(model.sourceAccessoryName(for: accessory))”")
                                .foregroundStyle(homeAccent)
                        }
                    } else {
                        NavigationLink {
                            IOSHomeAssistantAccessorySplitView(
                                candidates: splitCandidates,
                                selectedEntityIDs: $splitEntityIDs
                            )
                        } label: {
                            settingsRow(
                                title: "拆分配件…",
                                value: splitEntityIDs.isEmpty
                                    ? "已合并"
                                    : "\(splitEntityIDs.count) 个独立配件"
                            )
                        }
                    }
                } header: {
                    Text("群组")
                } footer: {
                    if accessory.isSplitAccessory {
                        Text("合并后，此控制会重新回到原物理设备内，不再单独显示卡片。")
                    } else {
                        Text("默认按 Home Assistant 物理设备合并。只有这里选中的控制实体会成为独立卡片，参数、提示和诊断实体不会自动拆分。")
                    }
                }
            }

            Section {
                NavigationLink {
                    IOSHomeAssistantEntityPickerView(
                        title: "主要控制实体",
                        entities: accessory.entities,
                        allowedDomains: Set(schema.primaryDomains),
                        selection: singleSelection($selectedPrimaryEntityID),
                        allowsEmptySelection: kind == .sensorGroup,
                        occupiedEntityNames: occupiedPrimaryEntities
                    )
                } label: {
                    bindingRow(
                        title: "主要控制实体",
                        entityID: selectedPrimaryEntityID,
                        fallback: kind == .sensorGroup ? "未选择" : "需要选择"
                    )
                }

                NavigationLink {
                    IOSHomeAssistantEntityPickerView(
                        title: "总开关实体",
                        entities: accessory.entities,
                        allowedDomains: HomeAssistantAccessorySchemaRegistry.allowedDomains(for: .power, kind: kind),
                        selection: singleSelection($selectedPowerEntityID),
                        allowsEmptySelection: true,
                        occupiedEntityNames: occupiedPrimaryEntities
                    )
                } label: {
                    bindingRow(title: "总开关实体", entityID: selectedPowerEntityID, fallback: "自动 / 无")
                }

                NavigationLink {
                    IOSHomeAssistantRoleBindingsView(
                        model: model,
                        accessory: accessory,
                        kind: kind,
                        bindings: $bindings
                    )
                } label: {
                    settingsRow(title: "状态与辅助实体", value: "\(auxiliaryBindingCount) 个")
                }

                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.warning)
                } else if accessory.needsReview, splitCandidates.count <= 1 {
                    Label("保存后将确认此设备的类型和主要控制实体。", systemImage: "checkmark.circle")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textSecondary)
                }
            } header: {
                Text("实体与状态")
            } footer: {
                Text("主状态和首页快捷操作只读取总开关或主要控制实体；风扇、指示灯等辅助实体不会把整台设备误判为开启。")
            }

            Section {
                Button(model.hiddenCardIDs.contains(accessory.id) ? "显示设备" : "隐藏设备") {
                    if model.hiddenCardIDs.contains(accessory.id) {
                        model.showDevice(accessory.id)
                    } else {
                        model.hideDevice(accessory.id)
                    }
                    dismiss()
                }

                if accessory.isUserConfigured || model.devicePresentations[accessory.id] != nil {
                    Button("恢复自动识别", role: .destructive) { reset() }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background((theme.isGeek ? Color.black : theme.backgroundSecondary).ignoresSafeArea())
        .navigationTitle("设备设置")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { save() }
                    .disabled(normalizedName.isEmpty || validationMessage != nil)
            }
        }
        .onChange(of: deviceName) { _, value in
            if value.count > 40 { deviceName = String(value.prefix(40)) }
        }
        .onChange(of: kind) { oldKind, newKind in
            if oldKind != newKind {
                selectedSystemImage = newKind.systemImage
            }
        }
        .accessibilityIdentifier("ios.homeAssistant.deviceEditor")
    }

    private var nameAndIconEditor: some View {
        HStack(spacing: 14) {
            NavigationLink {
                IOSHomeAssistantIconPickerView(
                    kind: kind,
                    selectedSystemImage: $selectedSystemImage
                )
            } label: {
                Image(systemName: selectedSystemImage)
                    .font(.system(size: 25, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(homeAccent)
                    .frame(width: 58, height: 58)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(homeAccent, lineWidth: 2)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("更换设备图标")

            TextField("设备名称", text: $deviceName)
                .font(theme.appFont.font(.headline, weight: .semibold))
                .focused($isNameFocused)
                .submitLabel(.done)

            if !deviceName.isEmpty {
                Button {
                    deviceName = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除设备名称")
            }
        }
        .frame(minHeight: 66)
    }

    private var roomPicker: some View {
        Picker("房间", selection: $selectedAreaID) {
            ForEach(roomOptions) { room in
                Text(room.name).tag(room.id)
            }
        }
        .labelsHidden()
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .frame(height: 170)
        .clipped()
        .accessibilityIdentifier("ios.homeAssistant.deviceEditor.roomPicker")
    }

    private var displayTypePicker: some View {
        Picker("显示为", selection: $kind) {
            ForEach(HomeAssistantAccessoryKind.allCases) { option in
                Text(option.displayName).tag(option)
            }
        }
        .labelsHidden()
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .frame(height: 170)
        .clipped()
        .accessibilityIdentifier("ios.homeAssistant.deviceEditor.displayTypePicker")
    }

    private func settingsRow(title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(theme.textPrimary)
            Spacer()
            Text(value)
                .foregroundStyle(homeAccent)
                .lineLimit(1)
        }
        .font(theme.appFont.font(.body, weight: .medium))
        .frame(minHeight: 34)
    }

    private func bindingRow(title: String, entityID: String, fallback: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).foregroundStyle(theme.textPrimary)
                Spacer()
                Text(entityName(entityID) ?? fallback).foregroundStyle(homeAccent)
            }
            if !entityID.isEmpty {
                Text(entityID)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .font(theme.appFont.font(.body, weight: .medium))
        .frame(minHeight: 38)
    }

    private var roomOptions: [HomeAssistantRoom] {
        model.editableRooms
            + [HomeAssistantRoom(
                id: HomeAssistantTopologyBuilder.unassignedAreaID,
                name: "不显示在家庭中"
            )]
    }

    private var selectedRoomName: String {
        roomOptions.first(where: { $0.id == selectedAreaID })?.name ?? "不显示在家庭中"
    }

    private var splitCandidates: [HomeAssistantEntity] {
        model.splitCandidates(for: accessory)
    }

    private var normalizedName: String {
        deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var schema: HomeAssistantAccessorySchema {
        HomeAssistantAccessorySchemaRegistry.schema(for: kind)
    }

    private var validationMessage: String? {
        if kind != .sensorGroup {
            guard !selectedPrimaryEntityID.isEmpty || !selectedPowerEntityID.isEmpty else {
                return "请选择主要控制实体或总开关实体"
            }
        }
        if !selectedPrimaryEntityID.isEmpty,
           !schema.primaryDomains.contains(entity(selectedPrimaryEntityID)?.domain ?? "") {
            return "当前主要控制实体与“\(kind.displayName)”类型不兼容，请重新选择"
        }
        if !selectedPowerEntityID.isEmpty,
           !HomeAssistantAccessorySchemaRegistry.allowedDomains(for: .power, kind: kind)
            .contains(entity(selectedPowerEntityID)?.domain ?? "") {
            return "当前总开关实体不兼容，请重新选择"
        }
        if incompatibleAuxiliaryBindingCount > 0 {
            return "有 \(incompatibleAuxiliaryBindingCount) 个状态或辅助实体与当前类型不兼容，请进入列表移除或重新选择"
        }
        return nil
    }

    private var incompatibleAuxiliaryBindingCount: Int {
        bindings
            .filter { ![.primaryControl, .power].contains($0.role) }
            .reduce(into: 0) { count, binding in
                guard schema.supportedRoles.contains(binding.role) else {
                    count += binding.entityIDs.count
                    return
                }
                let allowedDomains = HomeAssistantAccessorySchemaRegistry.allowedDomains(
                    for: binding.role,
                    kind: kind
                )
                count += binding.entityIDs.filter { entityID in
                    guard let entity = entity(entityID) else { return true }
                    return !allowedDomains.isEmpty && !allowedDomains.contains(entity.domain)
                }.count
            }
    }

    private var auxiliaryBindingCount: Int {
        bindings
            .filter { ![.primaryControl, .power].contains($0.role) }
            .flatMap(\.entityIDs)
            .count
    }

    private var homeAccent: Color { theme.warning }

    private var occupiedPrimaryEntities: [String: String] {
        model.allAccessories.reduce(into: [:]) { result, candidate in
            guard candidate.sourceCardID != accessory.sourceCardID else { return }
            if let entityID = candidate.primaryControlEntity?.entityID {
                result[entityID] = candidate.name
            }
            if let entityID = candidate.powerEntity?.entityID {
                result[entityID] = candidate.name
            }
        }
    }

    private func entity(_ entityID: String) -> HomeAssistantEntity? {
        accessory.entities.first { $0.entityID == entityID }
            ?? model.snapshot?.entities.first { $0.entityID == entityID }
    }

    private func entityName(_ entityID: String) -> String? {
        guard !entityID.isEmpty else { return nil }
        return entity(entityID).map(model.displayName(for:))
    }

    private func singleSelection(_ value: Binding<String>) -> Binding<Set<String>> {
        Binding(
            get: { value.wrappedValue.isEmpty ? [] : [value.wrappedValue] },
            set: { value.wrappedValue = $0.first ?? "" }
        )
    }

    private func reset() {
        model.resetDevicePresentation(cardID: accessory.id)
        if !accessory.isSplitAccessory {
            model.updateAccessoryGrouping(
                sourceCardID: accessory.sourceCardID,
                splitEntityIDs: []
            )
        }
        dismiss()
    }

    private func togglePicker(_ picker: InlinePicker) {
        withAnimation(.easeInOut(duration: 0.2)) {
            expandedPicker = expandedPicker == picker ? nil : picker
        }
    }

    private func save() {
        var updatedBindings = bindings.filter { ![.primaryControl, .power].contains($0.role) }
        if !selectedPrimaryEntityID.isEmpty {
            updatedBindings.append(.init(role: .primaryControl, entityIDs: [selectedPrimaryEntityID]))
        }
        if !selectedPowerEntityID.isEmpty {
            updatedBindings.append(.init(role: .power, entityIDs: [selectedPowerEntityID]))
        }
        model.updateAccessoryPresentation(
            accessoryID: accessory.id,
            customName: normalizedName,
            kind: kind,
            systemImage: selectedSystemImage,
            areaID: selectedAreaID,
            bindings: updatedBindings
        )
        if !accessory.isSplitAccessory {
            model.updateAccessoryGrouping(
                sourceCardID: accessory.sourceCardID,
                splitEntityIDs: splitEntityIDs
            )
        }
        dismiss()
    }
}

private extension IOSHomeAssistantDeviceEditorView {
    enum InlinePicker: Equatable {
        case room
        case displayType
    }
}

private struct IOSHomeAssistantAccessorySplitView: View {
    @Environment(\.themeTokens) private var theme
    let candidates: [HomeAssistantEntity]
    @Binding var selectedEntityIDs: Set<String>

    var body: some View {
        List {
            Section {
                ForEach(candidates) { entity in
                    Button {
                        if selectedEntityIDs.contains(entity.entityID) {
                            selectedEntityIDs.remove(entity.entityID)
                        } else {
                            selectedEntityIDs.insert(entity.entityID)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: systemImage(for: entity))
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(theme.warning)
                                .frame(width: 30)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(entity.name)
                                    .foregroundStyle(theme.textPrimary)
                                Text(entity.entityID)
                                    .font(theme.captionFont)
                                    .foregroundStyle(theme.textTertiary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if selectedEntityIDs.contains(entity.entityID) {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(theme.warning)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("选中的控制会在完成设备设置后成为独立配件。未选中的控制、状态和参数仍保留在原设备中。")
            }

            if !selectedEntityIDs.isEmpty {
                Section {
                    Button("全部重新合并", role: .destructive) {
                        selectedEntityIDs.removeAll()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background((theme.isGeek ? Color.black : theme.backgroundSecondary).ignoresSafeArea())
        .navigationTitle("拆分配件")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("ios.homeAssistant.accessorySplitPicker")
    }

    private func systemImage(for entity: HomeAssistantEntity) -> String {
        switch entity.domain {
        case "light": "lightbulb.fill"
        case "fan": "fan.fill"
        case "climate": "air.conditioner.horizontal.fill"
        case "cover": "curtains.closed"
        case "lock": "lock.fill"
        default: "switch.2"
        }
    }
}
