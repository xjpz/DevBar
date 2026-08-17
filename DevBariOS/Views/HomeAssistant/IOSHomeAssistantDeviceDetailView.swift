import DevBarCore
import SwiftUI

struct IOSHomeAssistantDeviceDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeTokens) private var theme
    @ObservedObject var model: IOSHomeAssistantViewModel
    let accessory: HomeAssistantAccessory

    @State private var confirmation: DetailConfirmation?
    @State private var errorMessage: String?
    @State private var editingAccessory: HomeAssistantAccessory?
    @State private var showsOtherEntities = false
    @State private var showsRawInformation = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                deviceIdentity
                syncNotice

                if liveAccessory.needsReview {
                    reviewNotice
                }

                entityGroup("主要控制", entities: mainControlEntities, controlsEnabled: true)
                entityGroup("状态指标", entities: statusEntities, controlsEnabled: false)
                entityGroup("辅助功能", entities: auxiliaryEntities, controlsEnabled: true)
                otherEntitiesSection
                rawInformationSection
            }
            .padding(16)
        }
        .background((theme.isGeek ? Color.black : theme.backgroundSecondary).ignoresSafeArea())
        .navigationTitle(liveAccessory.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button {
                        editingAccessory = liveAccessory
                    } label: {
                        Label("设备设置", systemImage: "gearshape")
                    }
                    if model.isShownOnDashboard(liveAccessory) {
                        Button(role: .destructive) {
                            model.hideDevice(liveAccessory.id)
                            dismiss()
                        } label: {
                            Label("从首页隐藏", systemImage: "eye.slash")
                        }
                    } else {
                        Button {
                            model.showDevice(liveAccessory.id)
                            dismiss()
                        } label: {
                            Label("显示在首页", systemImage: "eye")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
        .alert(item: $confirmation) { item in
            Alert(
                title: Text("确认操作"),
                message: Text("确定执行 \(item.call.domain).\(item.call.service) 吗？"),
                primaryButton: .destructive(Text("执行")) { execute(item.call) },
                secondaryButton: .cancel()
            )
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(item: $editingAccessory) { accessory in
            NavigationStack {
                IOSHomeAssistantDeviceEditorView(model: model, accessory: accessory)
            }
            .presentationDetents([.large])
        }
    }

    private var liveAccessory: HomeAssistantAccessory {
        model.accessory(id: accessory.id) ?? accessory
    }

    private var deviceIdentity: some View {
        Button {
            editingAccessory = liveAccessory
        } label: {
            HStack(spacing: 14) {
                Image(systemName: liveAccessory.systemImage)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(theme.info)
                    .frame(width: 54, height: 54)
                    .background(theme.info.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(liveAccessory.name)
                        .font(theme.appFont.font(.headline, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text("\(liveAccessory.kind.displayName) · \(model.roomName(for: liveAccessory))")
                        .font(theme.subheadlineFont)
                        .foregroundStyle(theme.textSecondary)
                    Text(model.semanticState(for: liveAccessory).primaryText)
                        .font(theme.captionWeightFont)
                        .foregroundStyle(theme.textTertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .iosGlassContainer(theme, cornerRadius: 22)
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(theme.borderSubtle, lineWidth: 1))
        .accessibilityLabel("编辑 \(liveAccessory.name)")
    }

    @ViewBuilder
    private var syncNotice: some View {
        if !model.canControlDevices {
            Label("设备状态同步完成后可操作", systemImage: "arrow.triangle.2.circlepath")
                .font(theme.subheadlineFont)
                .foregroundStyle(theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .iosGlassContainer(theme, cornerRadius: 18)
        }
    }

    private var reviewNotice: some View {
        Button {
            editingAccessory = liveAccessory
        } label: {
            Label("需要选择或确认主要控制实体，确认前不会执行快捷操作。", systemImage: "exclamationmark.circle.fill")
                .font(theme.subheadlineFont)
                .foregroundStyle(theme.warning)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .iosGlassContainer(theme, cornerRadius: 18)
    }

    private var mainControlEntities: [HomeAssistantEntity] {
        uniqueEntities(
            liveAccessory.entities(for: .power) + liveAccessory.entities(for: .primaryControl)
        )
    }

    private var statusEntities: [HomeAssistantEntity] {
        let roles: [HomeAssistantAccessoryRole] = [
            .temperature, .humidity, .airQuality, .particulateMatter,
            .filterLife, .powerUsage, .energyUsage, .activity, .alert,
        ]
        return uniqueEntities(roles.flatMap { liveAccessory.entities(for: $0) })
    }

    private var auxiliaryEntities: [HomeAssistantEntity] {
        let roles: [HomeAssistantAccessoryRole] = [.mode, .childControl, .indicator, .action]
        return uniqueEntities(roles.flatMap { liveAccessory.entities(for: $0) })
    }

    @ViewBuilder
    private func entityGroup(
        _ title: String,
        entities: [HomeAssistantEntity],
        controlsEnabled: Bool
    ) -> some View {
        if !entities.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(theme.captionWeightFont)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, 4)
                ForEach(entities) { entity in
                    entitySection(entity, controlsEnabled: controlsEnabled)
                }
            }
        }
    }

    private func entitySection(_ entity: HomeAssistantEntity, controlsEnabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.displayName(for: entity))
                        .font(theme.appFont.font(.headline, weight: .semibold))
                    Text(entity.entityID)
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                Text(model.stateText(for: entity))
                    .font(theme.subheadlineWeightFont)
                    .foregroundStyle(entity.isAvailable ? theme.brandPrimary : theme.textTertiary)
            }

            if controlsEnabled {
                controls(for: entity)
                    .disabled(!model.canControlDevices || !entity.isAvailable)
            } else {
                metricAttributes(entity)
            }
        }
        .padding(16)
        .iosGlassContainer(theme, cornerRadius: 22)
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(theme.borderSubtle, lineWidth: 1))
    }

    @ViewBuilder
    private func controls(for entity: HomeAssistantEntity) -> some View {
        switch entity.domain {
        case "light", "switch", "input_boolean":
            Button(entity.isOn ? "关闭" : "开启") {
                perform(entity, action: entity.isOn ? .turnOff : .turnOn)
            }
            .buttonStyle(.borderedProminent)
            if entity.domain == "light", entity.state.attributes["brightness"] != nil {
                percentageSlider(entity: entity, label: "亮度", attribute: "brightness", scale: 255) { .setBrightness($0) }
            }
        case "fan":
            fanControls(entity)
        case "cover":
            HStack {
                actionButton("打开", image: "arrow.up", entity: entity, action: .open)
                actionButton("停止", image: "stop.fill", entity: entity, action: .stop)
                actionButton("关闭", image: "arrow.down", entity: entity, action: .close)
            }
            if entity.state.attributes["current_position"] != nil {
                percentageSlider(entity: entity, label: "位置", attribute: "current_position") { .setCoverPosition($0) }
            }
        case "climate":
            climateControls(entity)
        case "select", "input_select":
            selectControl(entity)
        case "lock":
            Button(entity.state.state == "locked" ? "解锁" : "上锁", role: entity.state.state == "locked" ? .destructive : nil) {
                perform(entity, action: entity.state.state == "locked" ? .unlock : .lock)
            }
            .buttonStyle(.borderedProminent)
        case "scene", "script", "automation", "button":
            Button("执行") { perform(entity, action: .activate) }
                .buttonStyle(.borderedProminent)
        default:
            metricAttributes(entity)
        }
    }

    @ViewBuilder
    private func fanControls(_ entity: HomeAssistantEntity) -> some View {
        let capabilities = HomeAssistantFanCapabilities(entity: entity)
        Button(entity.isOn ? "关闭" : "开启") {
            perform(entity, action: entity.isOn ? .turnOff : .turnOn)
        }
        .buttonStyle(.borderedProminent)

        if capabilities.supportsPercentage {
            percentageSlider(
                entity: entity,
                label: "风速",
                attribute: "percentage",
                step: capabilities.percentageStep
            ) { .setPercentage($0) }
        }

        if !capabilities.presetModes.isEmpty {
            Menu {
                ForEach(capabilities.presetModes, id: \.self) { mode in
                    Button(model.attributeValue(
                        key: "preset_mode",
                        value: .string(mode),
                        entity: entity
                    ) ?? mode) {
                        perform(entity, action: .setPresetMode(mode))
                    }
                }
            } label: {
                Label(
                    "送风模式 · \(capabilities.presetMode.map { model.attributeValue(key: "preset_mode", value: .string($0), entity: entity) ?? $0 } ?? "未设置")",
                    systemImage: "wind"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }

        if capabilities.supportsOscillation {
            Button(capabilities.oscillating == true ? "关闭摆风" : "开启摆风") {
                perform(entity, action: .setOscillating(!(capabilities.oscillating ?? false)))
            }
            .buttonStyle(.bordered)
        }

        if capabilities.supportsDirection,
           let currentDirection = capabilities.currentDirection,
           let nextDirection = nextFanDirection(currentDirection) {
            Button("切换风向") {
                perform(entity, action: .setDirection(nextDirection))
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func climateControls(_ entity: HomeAssistantEntity) -> some View {
        let capabilities = HomeAssistantClimateCapabilities(entity: entity)

        if let powerAction = climatePowerAction(for: capabilities) {
            Button(capabilities.isOn ? "关闭" : "开启") {
                perform(entity, action: powerAction)
            }
            .buttonStyle(.borderedProminent)
        }

        if capabilities.supportsTargetTemperature,
           let temperature = capabilities.targetTemperature {
            Stepper(
                "目标温度 \(temperature.formatted(.number.precision(.fractionLength(0...1))))\(capabilities.temperatureUnit)",
                value: Binding(
                    get: { HomeAssistantClimateCapabilities(entity: entity).targetTemperature ?? temperature },
                    set: { perform(entity, action: .setTemperature($0)) }
                ),
                in: capabilities.temperatureRange,
                step: capabilities.temperatureStep
            )
        }

        if capabilities.supportsHVACMode {
            climateOptionMenu(
                entity: entity,
                title: "运行模式",
                image: "thermometer.medium",
                values: capabilities.hvacModes,
                selected: capabilities.hvacMode,
                attributeKey: "hvac_modes"
            ) { .setHVACMode($0) }
        }

        if capabilities.supportsFanMode {
            climateOptionMenu(
                entity: entity,
                title: "风速",
                image: "wind",
                values: capabilities.fanModes,
                selected: capabilities.fanMode,
                attributeKey: "fan_mode"
            ) { .setClimateFanMode($0) }
        }

        if capabilities.supportsSwingMode {
            climateOptionMenu(
                entity: entity,
                title: capabilities.supportsHorizontalSwingMode ? "上下摆风" : "摆风",
                image: "arrow.up.and.down",
                values: capabilities.swingModes,
                selected: capabilities.swingMode,
                attributeKey: "swing_mode"
            ) { .setClimateSwingMode($0) }
        }

        if capabilities.supportsHorizontalSwingMode {
            climateOptionMenu(
                entity: entity,
                title: "左右摆风",
                image: "arrow.left.and.right",
                values: capabilities.horizontalSwingModes,
                selected: capabilities.horizontalSwingMode,
                attributeKey: "swing_horizontal_mode"
            ) { .setClimateHorizontalSwingMode($0) }
        }

        if capabilities.supportsPresetMode {
            climateOptionMenu(
                entity: entity,
                title: "预设模式",
                image: "sparkles",
                values: capabilities.presetModes,
                selected: capabilities.presetMode,
                attributeKey: "preset_mode"
            ) { .setClimatePresetMode($0) }
        }
    }

    private func climateOptionMenu(
        entity: HomeAssistantEntity,
        title: String,
        image: String,
        values: [String],
        selected: String?,
        attributeKey: String,
        action: @escaping (String) -> HomeAssistantControlAction
    ) -> some View {
        Menu {
            ForEach(values, id: \.self) { value in
                Button(climateOptionTitle(value, key: attributeKey, entity: entity)) {
                    perform(entity, action: action(value))
                }
            }
        } label: {
            Label(
                "\(title) · \(selected.map { climateOptionTitle($0, key: attributeKey, entity: entity) } ?? "未设置")",
                systemImage: image
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private func climateOptionTitle(
        _ value: String,
        key: String,
        entity: HomeAssistantEntity?
    ) -> String {
        let fallbackKey = key == "swing_horizontal_mode" ? "swing_mode" : key
        guard let entity else {
            return HomeAssistantStateFormatter.translatedAttributeState(value, key: fallbackKey)
        }
        return model.attributeValue(key: key, value: .string(value), entity: entity)
            ?? HomeAssistantStateFormatter.translatedAttributeState(value, key: fallbackKey)
    }

    private func climatePowerAction(
        for capabilities: HomeAssistantClimateCapabilities
    ) -> HomeAssistantControlAction? {
        if capabilities.isOn {
            if capabilities.supportsTurnOff { return .turnOff }
            if capabilities.hvacModes.contains("off") { return .setHVACMode("off") }
            return nil
        }
        return capabilities.supportsTurnOn ? .turnOn : nil
    }

    private func selectControl(_ entity: HomeAssistantEntity) -> some View {
        let options = entity.state.attributes["options"]?.arrayValue?.compactMap(\.stringValue) ?? []
        return Menu {
            ForEach(options, id: \.self) { option in
                Button(option) {
                    perform(entity, action: .selectOption(option))
                }
            }
        } label: {
            Label("选择 · \(model.stateText(for: entity))", systemImage: "list.bullet")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(options.isEmpty || !entity.availableServices.contains("select_option"))
    }

    private func percentageSlider(
        entity: HomeAssistantEntity,
        label: String,
        attribute: String,
        scale: Double = 100,
        step: Double = 1,
        action: @escaping (Double) -> HomeAssistantControlAction
    ) -> some View {
        let current = (entity.state.attributes[attribute]?.doubleValue ?? 0) / scale * 100
        return HomeAssistantPercentageControl(
            label: label,
            initialValue: current,
            step: step,
            theme: theme
        ) { value in
            perform(entity, action: action(value))
        }
    }

    private func nextFanDirection(_ currentDirection: String) -> String? {
        switch currentDirection.lowercased() {
        case "forward": "reverse"
        case "reverse", "backward": "forward"
        default: nil
        }
    }

    private func actionButton(
        _ title: String,
        image: String,
        entity: HomeAssistantEntity,
        action: HomeAssistantControlAction
    ) -> some View {
        Button { perform(entity, action: action) } label: {
            Label(title, systemImage: image).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private func metricAttributes(_ entity: HomeAssistantEntity) -> some View {
        let attributes = displayAttributes(entity)
        if !attributes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(attributes, id: \.0) { key, value in
                    HStack {
                        Text(key).foregroundStyle(theme.textSecondary)
                        Spacer()
                        Text(value).foregroundStyle(theme.textPrimary)
                    }
                    .font(theme.subheadlineFont)
                }
            }
        }
    }

    private var otherEntitiesSection: some View {
        DisclosureGroup(isExpanded: $showsOtherEntities) {
            VStack(spacing: 10) {
                ForEach(liveAccessory.otherEntities) { entity in
                    compactEntityRow(entity)
                }
            }
            .padding(.top, 10)
        } label: {
            Label("其他实体（\(liveAccessory.otherEntities.count)）", systemImage: "square.stack.3d.up")
                .font(theme.subheadlineWeightFont)
        }
        .padding(16)
        .iosGlassContainer(theme, cornerRadius: 22)
    }

    private var rawInformationSection: some View {
        DisclosureGroup(isExpanded: $showsRawInformation) {
            VStack(spacing: 10) {
                ForEach(liveAccessory.entities) { entity in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entity.entityID)
                            .font(theme.captionWeightFont)
                        ForEach(rawAttributes(entity), id: \.0) { key, value in
                            HStack(alignment: .top) {
                                Text(key).foregroundStyle(theme.textTertiary)
                                Spacer()
                                Text(value).multilineTextAlignment(.trailing)
                            }
                            .font(theme.captionFont)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if entity.id != liveAccessory.entities.last?.id { Divider() }
                }
            }
            .padding(.top, 10)
        } label: {
            Label("原始信息", systemImage: "chevron.left.forwardslash.chevron.right")
                .font(theme.subheadlineWeightFont)
        }
        .padding(16)
        .iosGlassContainer(theme, cornerRadius: 22)
    }

    private func compactEntityRow(_ entity: HomeAssistantEntity) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName(for: entity))
                    .foregroundStyle(theme.textPrimary)
                Text(entity.entityID)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            Text(model.stateText(for: entity))
                .font(theme.subheadlineFont)
                .foregroundStyle(entity.isAvailable ? theme.textSecondary : theme.textTertiary)
        }
    }

    private func displayAttributes(_ entity: HomeAssistantEntity) -> [(String, String)] {
        let keys: [String]
        switch entity.domain {
        case "climate": keys = ["current_temperature", "temperature", "current_humidity", "fan_mode", "swing_mode", "swing_horizontal_mode", "preset_mode", "hvac_action"]
        case "fan": keys = ["percentage", "preset_mode", "oscillating", "current_direction"]
        case "cover": keys = ["current_position"]
        default: keys = []
        }
        return keys.compactMap { key in
            guard let value = entity.state.attributes[key],
                  let formatted = model.attributeValue(key: key, value: value, entity: entity) else {
                return nil
            }
            return (model.attributeName(key, entity: entity), formatted)
        }
    }

    private func rawAttributes(_ entity: HomeAssistantEntity) -> [(String, String)] {
        entity.state.attributes
            .filter { !["friendly_name", "icon"].contains($0.key) }
            .compactMap { key, value in
                model.attributeValue(key: key, value: value, entity: entity).map { (key, $0) }
            }
            .sorted { $0.0 < $1.0 }
    }

    private func uniqueEntities(_ entities: [HomeAssistantEntity]) -> [HomeAssistantEntity] {
        var seen = Set<String>()
        return entities.filter { seen.insert($0.entityID).inserted }
    }

    private func perform(_ entity: HomeAssistantEntity, action: HomeAssistantControlAction) {
        do {
            let call = try HomeAssistantControlPolicy.serviceCall(entity: entity, action: action)
            if call.requiresConfirmation {
                confirmation = DetailConfirmation(call: call)
            } else {
                execute(call)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func execute(_ call: HomeAssistantServiceCall) {
        Task {
            do { try await model.execute(call) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct DetailConfirmation: Identifiable {
    let id = UUID()
    let call: HomeAssistantServiceCall
}

private struct HomeAssistantPercentageControl: View {
    let label: String
    let initialValue: Double
    let step: Double
    let theme: IOSThemeTokens
    let commit: (Double) -> Void
    @State private var value: Double

    init(
        label: String,
        initialValue: Double,
        step: Double = 1,
        theme: IOSThemeTokens,
        commit: @escaping (Double) -> Void
    ) {
        self.label = label
        self.initialValue = initialValue
        self.step = step
        self.theme = theme
        self.commit = commit
        _value = State(initialValue: initialValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(label) \(Int(value))%")
                .font(theme.captionWeightFont)
                .foregroundStyle(theme.textSecondary)
            Slider(value: $value, in: 0...100, step: step) { isEditing in
                if !isEditing { commit(value) }
            }
        }
        .onChange(of: initialValue) { _, newValue in
            value = newValue
        }
    }
}
