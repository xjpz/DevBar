import DevBarCore
import SwiftUI

struct IOSHomeAssistantEntityPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeTokens) private var theme
    let title: String
    let entities: [HomeAssistantEntity]
    let allowedDomains: Set<String>
    @Binding var selection: Set<String>
    let allowsMultipleSelection: Bool
    let allowsEmptySelection: Bool
    let occupiedEntityNames: [String: String]

    @State private var query = ""

    init(
        title: String,
        entities: [HomeAssistantEntity],
        allowedDomains: Set<String>,
        selection: Binding<Set<String>>,
        allowsMultipleSelection: Bool = false,
        allowsEmptySelection: Bool = false,
        occupiedEntityNames: [String: String] = [:]
    ) {
        self.title = title
        self.entities = entities
        self.allowedDomains = allowedDomains
        _selection = selection
        self.allowsMultipleSelection = allowsMultipleSelection
        self.allowsEmptySelection = allowsEmptySelection
        self.occupiedEntityNames = occupiedEntityNames
    }

    var body: some View {
        List {
            if allowsEmptySelection {
                Section {
                    Button {
                        selection.removeAll()
                        if !allowsMultipleSelection { dismiss() }
                    } label: {
                        HStack {
                            Label("不绑定", systemImage: "minus.circle")
                                .foregroundStyle(theme.textPrimary)
                            Spacer()
                            if selection.isEmpty {
                                Image(systemName: "checkmark").foregroundStyle(theme.warning)
                            }
                        }
                    }
                }
            }

            if availableEntities.isEmpty, unavailableEntities.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                entitySection("可用实体", entities: availableEntities)
                entitySection("不可用实体", entities: unavailableEntities)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background((theme.isGeek ? Color.black : theme.backgroundSecondary).ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "搜索名称或 entity_id")
        .toolbar {
            if allowsMultipleSelection {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("ios.homeAssistant.entityPicker")
    }

    @ViewBuilder
    private func entitySection(_ title: String, entities: [HomeAssistantEntity]) -> some View {
        if !entities.isEmpty {
            Section(title) {
                ForEach(entities) { entity in
                    Button {
                        updateSelection(entity.entityID)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: symbol(for: entity))
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(entity.isAvailable ? theme.info : theme.textTertiary)
                                .frame(width: 34, height: 34)
                                .background(theme.surfaceSecondary, in: Circle())

                            VStack(alignment: .leading, spacing: 3) {
                                Text(entity.name)
                                    .foregroundStyle(theme.textPrimary)
                                Text(entity.entityID)
                                    .font(theme.captionFont)
                                    .foregroundStyle(theme.textTertiary)
                                    .lineLimit(1)
                                HStack(spacing: 5) {
                                    Text(metadata(for: entity))
                                    if let occupant = occupiedEntityNames[entity.entityID] {
                                        Text("· 已用于 \(occupant)")
                                            .foregroundStyle(theme.warning)
                                    }
                                }
                                .font(theme.captionFont)
                                .foregroundStyle(theme.textSecondary)
                            }

                            Spacer()

                            if selection.contains(entity.entityID) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(theme.warning)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var filteredEntities: [HomeAssistantEntity] {
        var seen = Set<String>()
        return entities
            .filter { allowedDomains.isEmpty || allowedDomains.contains($0.domain) }
            .filter { entity in
                guard !query.isEmpty else { return true }
                let text = "\(entity.name) \(entity.entityID) \(entity.domain) \(entity.deviceClass ?? "")"
                return text.localizedCaseInsensitiveContains(query)
            }
            .filter { seen.insert($0.entityID).inserted }
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private var availableEntities: [HomeAssistantEntity] {
        filteredEntities.filter(\.isAvailable)
    }

    private var unavailableEntities: [HomeAssistantEntity] {
        filteredEntities.filter { !$0.isAvailable }
    }

    private func updateSelection(_ entityID: String) {
        if allowsMultipleSelection {
            if selection.contains(entityID) {
                selection.remove(entityID)
            } else {
                selection.insert(entityID)
            }
        } else {
            selection = [entityID]
            dismiss()
        }
    }

    private func metadata(for entity: HomeAssistantEntity) -> String {
        [entity.domain, entity.deviceClass, HomeAssistantStateFormatter.stateText(for: entity)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func symbol(for entity: HomeAssistantEntity) -> String {
        switch entity.domain {
        case "light": "lightbulb.fill"
        case "fan": "fan.fill"
        case "climate": "air.conditioner.horizontal.fill"
        case "sensor", "binary_sensor": "sensor.fill"
        case "switch", "input_boolean": "switch.2"
        case "button": "button.programmable"
        default: "circle.grid.2x2.fill"
        }
    }
}

struct IOSHomeAssistantRoleBindingsView: View {
    @Environment(\.themeTokens) private var theme
    @ObservedObject var model: IOSHomeAssistantViewModel
    let accessory: HomeAssistantAccessory
    let kind: HomeAssistantAccessoryKind
    @Binding var bindings: [HomeAssistantRoleBinding]

    var body: some View {
        List {
            roleSection("状态与传感器", roles: statusRoles)
            roleSection("辅助功能", roles: auxiliaryRoles)
            if !unsupportedBindings.isEmpty {
                Section("与当前类型不兼容") {
                    ForEach(unsupportedBindings, id: \.role) { binding in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(binding.role.displayName)
                                Text(binding.entityIDs.joined(separator: "、"))
                                    .font(theme.captionFont)
                                    .foregroundStyle(theme.textTertiary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Button("移除", role: .destructive) {
                                bindings.removeAll { $0.role == binding.role }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background((theme.isGeek ? Color.black : theme.backgroundSecondary).ignoresSafeArea())
        .navigationTitle("状态与辅助实体")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func roleSection(_ title: String, roles: [HomeAssistantAccessoryRole]) -> some View {
        if !roles.isEmpty {
            Section(title) {
                ForEach(roles) { role in
                    NavigationLink {
                        IOSHomeAssistantEntityPickerView(
                            title: role.displayName,
                            entities: candidates(for: role),
                            allowedDomains: HomeAssistantAccessorySchemaRegistry.allowedDomains(for: role, kind: kind),
                            selection: selection(for: role),
                            allowsMultipleSelection: allowsMultiple(role),
                            allowsEmptySelection: true,
                            occupiedEntityNames: occupiedPrimaryEntities
                        )
                    } label: {
                        HStack {
                            Text(role.displayName)
                            Spacer()
                            Text(selectionText(for: role))
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private var supportedRoles: Set<HomeAssistantAccessoryRole> {
        HomeAssistantAccessorySchemaRegistry.schema(for: kind).supportedRoles
    }

    private var unsupportedBindings: [HomeAssistantRoleBinding] {
        bindings.filter {
            ![.primaryControl, .power].contains($0.role) && !supportedRoles.contains($0.role)
        }
    }

    private var statusRoles: [HomeAssistantAccessoryRole] {
        [
            .temperature, .humidity, .airQuality, .particulateMatter,
            .filterLife, .powerUsage, .energyUsage, .activity, .alert,
        ].filter { supportedRoles.contains($0) }
    }

    private var auxiliaryRoles: [HomeAssistantAccessoryRole] {
        [.mode, .childControl, .indicator, .action].filter { supportedRoles.contains($0) }
    }

    private func candidates(for role: HomeAssistantAccessoryRole) -> [HomeAssistantEntity] {
        if [.temperature, .humidity, .airQuality, .particulateMatter, .filterLife, .activity, .alert].contains(role) {
            return model.snapshot?.entities ?? accessory.entities
        }
        return accessory.entities
    }

    private func selection(for role: HomeAssistantAccessoryRole) -> Binding<Set<String>> {
        Binding(
            get: {
                Set(bindings.first(where: { $0.role == role })?.entityIDs ?? [])
            },
            set: { selectedIDs in
                bindings.removeAll { $0.role == role }
                if !selectedIDs.isEmpty {
                    bindings.append(
                        HomeAssistantRoleBinding(role: role, entityIDs: selectedIDs.sorted())
                    )
                }
            }
        )
    }

    private func selectionText(for role: HomeAssistantAccessoryRole) -> String {
        let count = bindings.first(where: { $0.role == role })?.entityIDs.count ?? 0
        return count == 0 ? "未绑定" : "\(count) 个"
    }

    private func allowsMultiple(_ role: HomeAssistantAccessoryRole) -> Bool {
        [.childControl, .indicator, .activity, .alert, .action].contains(role)
    }

    private var occupiedPrimaryEntities: [String: String] {
        model.allAccessories.reduce(into: [:]) { result, candidate in
            guard candidate.id != accessory.id else { return }
            if let entityID = candidate.primaryControlEntity?.entityID {
                result[entityID] = candidate.name
            }
            if let entityID = candidate.powerEntity?.entityID {
                result[entityID] = candidate.name
            }
        }
    }
}
