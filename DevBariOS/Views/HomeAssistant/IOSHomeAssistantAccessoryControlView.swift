import DevBarCore
import SwiftUI

struct IOSHomeAssistantAccessoryControlView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeTokens) private var theme
    @ObservedObject var model: IOSHomeAssistantViewModel
    let accessory: HomeAssistantAccessory

    @State private var editingAccessory: HomeAssistantAccessory?
    @State private var confirmation: AccessoryControlConfirmation?
    @State private var errorMessage: String?
    @State private var dismissalOffset: CGFloat = 0

    var body: some View {
        ZStack {
            controlBackground
                .contentShape(Rectangle())
                .onTapGesture {
                    dismiss()
                }
                .simultaneousGesture(dismissDragGesture)

            VStack(spacing: controlProjection.usesChildControlGrid ? 12 : 18) {
                topBar
                    .contentShape(Rectangle())
                    .simultaneousGesture(dismissDragGesture)

                VStack(spacing: 4) {
                    Text(liveAccessory.name)
                        .font(theme.appFont.font(.largeTitle, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(semanticState.primaryText)
                        .font(theme.appFont.font(.title3, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                }

                if usesScrollableControlSurface {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 14) {
                            controlSurface
                                .disabled(!model.canControlDevices || isPending)
                            auxiliaryControls
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                } else {
                    Spacer(minLength: controlProjection.usesChildControlGrid ? 0 : 8)
                    controlSurface
                        .disabled(!model.canControlDevices || isPending)
                    if controlProjection.usesChildControlGrid {
                        childControlGrid
                    }
                    auxiliaryControls
                    Spacer(minLength: controlProjection.usesChildControlGrid ? 0 : 8)
                }
                bottomBar
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .offset(y: dismissalOffset)
        .scaleEffect(dismissalScale, anchor: .center)
        .toolbar(.hidden, for: .navigationBar)
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
        .accessibilityIdentifier("ios.homeAssistant.accessoryControl")
        .accessibilityAction(named: "关闭") {
            dismiss()
        }
    }

    private var liveAccessory: HomeAssistantAccessory {
        model.accessory(id: accessory.id) ?? accessory
    }

    private var semanticState: HomeAssistantAccessorySemanticState {
        model.semanticState(for: liveAccessory)
    }

    private var controlProjection: HomeAssistantAccessoryControlProjection {
        HomeAssistantAccessoryControlProjection(accessory: liveAccessory)
    }

    private var controlEntity: HomeAssistantEntity? {
        controlProjection.masterEntity
    }

    private var isPending: Bool {
        controlEntity.map { model.pendingEntityIDs.contains($0.entityID) } ?? false
    }

    private var usesScrollableControlSurface: Bool {
        controlEntity?.domain == "climate"
    }

    private var dismissalScale: CGFloat {
        1 - min(dismissalOffset / 220, 1) * 0.035
    }

    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                guard value.translation.height > 0,
                      abs(value.translation.width) < value.translation.height else { return }
                dismissalOffset = min(220, value.translation.height)
            }
            .onEnded { value in
                let downwardDistance = max(
                    value.translation.height,
                    value.predictedEndTranslation.height
                )
                if downwardDistance > 100,
                   abs(value.translation.width) < downwardDistance {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        dismissalOffset = 0
                    }
                }
            }
    }

    private var topBar: some View {
        HStack {
            Spacer()

            if !model.canControlDevices {
                Label("仅查看", systemImage: "wifi.slash")
                    .font(theme.captionWeightFont)
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .frame(minHeight: 48)
    }

    @ViewBuilder
    private var controlSurface: some View {
        if semanticState.availability == .unavailable || semanticState.availability == .unknown {
            unavailableSurface
        } else if let entity = controlEntity {
            switch entity.domain {
            case "light":
                levelControl(
                    entity: entity,
                    value: lightLevel(entity),
                    symbol: liveAccessory.systemImage,
                    accent: .yellow,
                    supportsLevel: entity.state.attributes["brightness"] != nil,
                    compact: controlProjection.usesChildControlGrid,
                    levelAction: { .setBrightness($0) }
                )
            case "fan":
                fanControl(entity)
            case "switch", "input_boolean":
                levelControl(
                    entity: entity,
                    value: entity.isOn ? 100 : 0,
                    symbol: liveAccessory.systemImage,
                    accent: .yellow,
                    supportsLevel: false,
                    compact: controlProjection.usesChildControlGrid,
                    levelAction: nil
                )
            case "climate":
                climateControl(entity)
            case "cover":
                coverControl(entity)
            case "lock":
                lockControl(entity)
            case "scene", "script", "automation", "button":
                actionControl(entity)
            default:
                metricControl(entity)
            }
        } else {
            metricSummary
        }
    }

    private func fanControl(_ entity: HomeAssistantEntity) -> some View {
        let capabilities = HomeAssistantFanCapabilities(entity: entity)
        return IOSHomeAssistantFanControlPanel(
            isOn: entity.isOn,
            percentage: capabilities.percentage,
            percentageStep: capabilities.percentageStep,
            supportsPercentage: capabilities.supportsPercentage,
            presetModes: capabilities.presetModes,
            selectedPresetMode: capabilities.presetMode,
            supportsOscillation: capabilities.supportsOscillation,
            isOscillating: capabilities.oscillating,
            supportsDirection: capabilities.supportsDirection,
            currentDirection: capabilities.currentDirection,
            symbol: liveAccessory.systemImage,
            theme: theme,
            titleForPreset: { mode in
                model.attributeValue(
                    key: "preset_mode",
                    value: .string(mode),
                    entity: entity
                ) ?? mode
            },
            togglePower: {
                perform(entity, action: entity.isOn ? .turnOff : .turnOn)
            },
            setPercentage: { value in
                perform(entity, action: .setPercentage(value))
            },
            setPresetMode: { mode in
                perform(entity, action: .setPresetMode(mode))
            },
            setOscillating: { value in
                perform(entity, action: .setOscillating(value))
            },
            setDirection: { value in
                perform(entity, action: .setDirection(value))
            }
        )
        .frame(maxWidth: 360)
    }

    private func levelControl(
        entity: HomeAssistantEntity,
        value: Double,
        symbol: String,
        accent: Color,
        supportsLevel: Bool,
        compact: Bool,
        levelAction: ((Double) -> HomeAssistantControlAction)?
    ) -> some View {
        let controlHeight: CGFloat = compact ? 324 : 390
        let controlWidth: CGFloat = compact ? 132 : 154
        return IOSHomeAssistantVerticalLevelControl(
            value: value,
            isOn: entity.isOn,
            symbol: symbol,
            accent: accent,
            supportsLevel: supportsLevel,
            isPending: model.pendingEntityIDs.contains(entity.entityID),
            controlWidth: controlWidth,
            controlHeight: controlHeight,
            toggle: {
                perform(entity, action: entity.isOn ? .turnOff : .turnOn)
            },
            commit: { value in
                guard let levelAction else { return }
                perform(entity, action: levelAction(value))
            }
        )
        .frame(height: controlHeight)
    }

    private func climateControl(_ entity: HomeAssistantEntity) -> some View {
        let capabilities = HomeAssistantClimateCapabilities(entity: entity)
        return IOSHomeAssistantClimateControlPanel(
            capabilities: capabilities,
            symbol: liveAccessory.systemImage,
            theme: theme,
            titleForValue: { key, value in
                model.attributeValue(
                    key: key,
                    value: .string(value),
                    entity: entity
                ) ?? HomeAssistantStateFormatter.translatedAttributeState(
                    value,
                    key: key == "swing_horizontal_mode" ? "swing_mode" : key
                )
            },
            togglePower: climatePowerAction(for: capabilities).map { action in
                { perform(entity, action: action) }
            },
            setTemperature: { value in
                perform(entity, action: .setTemperature(value))
            },
            setHVACMode: { mode in
                perform(entity, action: .setHVACMode(mode))
            },
            setFanMode: { mode in
                perform(entity, action: .setClimateFanMode(mode))
            },
            setPresetMode: { mode in
                perform(entity, action: .setClimatePresetMode(mode))
            },
            setSwingMode: { mode in
                perform(entity, action: .setClimateSwingMode(mode))
            },
            setHorizontalSwingMode: { mode in
                perform(entity, action: .setClimateHorizontalSwingMode(mode))
            }
        )
        .frame(maxWidth: 390)
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

    private func coverControl(_ entity: HomeAssistantEntity) -> some View {
        VStack(spacing: 24) {
            Image(systemName: liveAccessory.systemImage)
                .font(.system(size: 76, weight: .medium))
                .foregroundStyle(.white)
            HStack(spacing: 16) {
                controlButton("打开", image: "arrow.up", entity: entity, action: .open)
                controlButton("停止", image: "stop.fill", entity: entity, action: .stop)
                controlButton("关闭", image: "arrow.down", entity: entity, action: .close)
            }
        }
    }

    private func lockControl(_ entity: HomeAssistantEntity) -> some View {
        Button {
            perform(entity, action: entity.state.state == "locked" ? .unlock : .lock)
        } label: {
            VStack(spacing: 18) {
                Image(systemName: entity.state.state == "locked" ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 76, weight: .medium))
                Text(entity.state.state == "locked" ? "解锁" : "上锁")
                    .font(theme.appFont.font(.title2, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(width: 250, height: 250)
            .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func actionControl(_ entity: HomeAssistantEntity) -> some View {
        Button {
            perform(entity, action: .activate)
        } label: {
            VStack(spacing: 18) {
                Image(systemName: liveAccessory.systemImage)
                    .font(.system(size: 72, weight: .medium))
                Text("执行")
                    .font(theme.appFont.font(.title2, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(width: 250, height: 250)
            .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func metricControl(_ entity: HomeAssistantEntity) -> some View {
        VStack(spacing: 18) {
            Image(systemName: liveAccessory.systemImage)
                .font(.system(size: 68, weight: .medium))
                .foregroundStyle(controlAccent)
            Text(model.stateText(for: entity))
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
        }
    }

    private var metricSummary: some View {
        VStack(spacing: 16) {
            Image(systemName: liveAccessory.systemImage)
                .font(.system(size: 70, weight: .medium))
                .foregroundStyle(controlAccent)
            Text(semanticState.primaryText)
                .font(theme.appFont.font(.title, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private var unavailableSurface: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.white.opacity(0.7))
            Text(semanticState.primaryText)
                .font(theme.appFont.font(.title2, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private var auxiliaryControls: some View {
        let auxiliary = auxiliaryControlEntities
        if !auxiliary.isEmpty {
            if usesScrollableControlSurface {
                VStack(alignment: .leading, spacing: 10) {
                    Text("辅助功能")
                        .font(theme.captionWeightFont)
                        .foregroundStyle(.white.opacity(0.64))

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10),
                        ],
                        spacing: 10
                    ) {
                        ForEach(auxiliary) { entity in
                            auxiliaryControl(entity)
                        }
                    }
                }
                .frame(maxWidth: 390)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(auxiliary) { entity in
                            auxiliaryControl(entity)
                        }
                    }
                }
                .contentMargins(.horizontal, 0, for: .scrollContent)
            }
        }
    }

    @ViewBuilder
    private func auxiliaryControl(_ entity: HomeAssistantEntity) -> some View {
        if ["select", "input_select"].contains(entity.domain) {
            let options = entity.state.attributes["options"]?.arrayValue?.compactMap(\.stringValue) ?? []
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(option) {
                        perform(entity, action: .selectOption(option))
                    }
                }
            } label: {
                auxiliaryControlLabel(entity, showsDisclosure: true)
            }
            .buttonStyle(.plain)
            .disabled(
                !model.canControlDevices
                    || !entity.isAvailable
                    || model.pendingEntityIDs.contains(entity.entityID)
                    || options.isEmpty
                    || !entity.availableServices.contains("select_option")
            )
        } else {
            let action = HomeAssistantControlPolicy.quickAction(for: entity)
            Button {
                if let action { perform(entity, action: action) }
            } label: {
                auxiliaryControlLabel(entity, showsDisclosure: false)
            }
            .buttonStyle(.plain)
            .disabled(
                !model.canControlDevices
                    || !entity.isAvailable
                    || model.pendingEntityIDs.contains(entity.entityID)
                    || action == nil
            )
        }
    }

    private func auxiliaryControlLabel(
        _ entity: HomeAssistantEntity,
        showsDisclosure: Bool
    ) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName(for: entity))
                    .font(theme.captionWeightFont)
                    .lineLimit(1)
                Text(model.stateText(for: entity))
                    .font(theme.captionFont)
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if showsDisclosure {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.56))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(minWidth: 112, minHeight: 58, alignment: .leading)
        .background(
            entity.isOn ? controlAccent.opacity(0.18) : Color.clear,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 0.75)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.displayName(for: entity))，\(model.stateText(for: entity))")
    }

    private var auxiliaryControlEntities: [HomeAssistantEntity] {
        let roles: [HomeAssistantAccessoryRole] = [.power, .mode, .childControl, .indicator, .action]
        let childEntityIDs = Set(controlProjection.childEntities.map(\.entityID))
        var seen = Set<String>()
        return roles
            .flatMap { liveAccessory.entities(for: $0) }
            .filter {
                $0.entityID != controlEntity?.entityID
                    && !childEntityIDs.contains($0.entityID)
                    && seen.insert($0.entityID).inserted
            }
    }

    private var childControlGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
            ],
            spacing: 10
        ) {
            ForEach(controlProjection.childEntities) { entity in
                childControlCard(entity)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func childControlCard(_ entity: HomeAssistantEntity) -> some View {
        let action = HomeAssistantControlPolicy.quickAction(for: entity)
        let isEnabled = model.canControlDevices
            && entity.isAvailable
            && !model.pendingEntityIDs.contains(entity.entityID)
            && action != nil
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        return Button {
            if let action {
                perform(entity, action: action)
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            entity.isOn
                                ? controlAccent.opacity(0.28)
                                : theme.textPrimary.opacity(theme.isGeek ? 0.18 : 0.14)
                        )
                    Image(systemName: childControlSystemImage(for: entity))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(
                            entity.isOn
                                ? controlAccent
                                : theme.textPrimary.opacity(theme.isGeek ? 0.78 : 0.68)
                        )
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 1) {
                    Text(model.displayName(for: entity))
                        .font(theme.captionWeightFont)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    Text(model.stateText(for: entity))
                        .font(theme.captionFont)
                        .foregroundStyle(
                            entity.isOn
                                ? controlAccent
                                : theme.textPrimary.opacity(theme.isGeek ? 0.68 : 0.58)
                        )
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 60, maxHeight: 60, alignment: .leading)
            .background(.regularMaterial, in: shape)
            .background(
                entity.isOn
                    ? controlAccent.opacity(theme.isGeek ? 0.18 : 0.14)
                    : theme.textPrimary.opacity(theme.isGeek ? 0.10 : 0.12),
                in: shape
            )
            .overlay(
                shape.stroke(
                    theme.textPrimary.opacity(theme.isGeek ? 0.14 : 0.10),
                    lineWidth: 0.75
                )
            )
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(isEnabled)
        .opacity(entity.isAvailable ? 1 : 0.58)
        .accessibilityIdentifier("ios.homeAssistant.childControl.\(entity.entityID)")
        .accessibilityLabel("\(model.displayName(for: entity))，\(model.stateText(for: entity))")
        .accessibilityHint(isEnabled ? "轻点切换" : "当前不可控制")
    }

    private func childControlSystemImage(for entity: HomeAssistantEntity) -> String {
        let name = model.displayName(for: entity).lowercased()
        if name.contains("usb") { return "cable.connector" }
        if name.contains("指示灯") || name.contains("indicator") || name.contains("led") {
            return "lightbulb.fill"
        }
        switch entity.domain {
        case "light": return "lightbulb.fill"
        case "fan": return "fan.fill"
        default: return "powerplug.fill"
        }
    }

    private var bottomBar: some View {
        HStack {
            Spacer()
            glassCircleButton("gearshape.fill", diameter: 56) {
                editingAccessory = liveAccessory
            }
            .accessibilityLabel("设备设置")
        }
    }

    private var controlBackground: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            LinearGradient(
                colors: [
                    controlAccent.opacity(theme.isGeek ? 0.18 : 0.13),
                    Color.white.opacity(theme.isGeek ? 0.015 : 0.09),
                    Color.black.opacity(theme.isGeek ? 0.20 : 0.06),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    private var controlAccent: Color {
        switch liveAccessory.kind {
        case .light, .switchDevice: .yellow
        case .fan, .airPurifier, .airConditioner: .cyan
        case .sensorGroup: .mint
        case .generic: theme.brandPrimary
        }
    }

    private func lightLevel(_ entity: HomeAssistantEntity) -> Double {
        guard entity.isOn else { return 0 }
        return (entity.state.attributes["brightness"]?.doubleValue ?? 255) / 255 * 100
    }

    private func roundActionButton(_ image: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func glassCircleButton(
        _ image: String,
        diameter: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.system(size: diameter * 0.40, weight: .semibold))
                .foregroundStyle(theme.textPrimary.opacity(0.88))
                .frame(width: diameter, height: diameter)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                    Circle()
                        .fill(.white.opacity(theme.isGeek ? 0.06 : 0.12))
                }
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.18), lineWidth: 0.75)
                )
                .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }

    private func controlButton(
        _ title: String,
        image: String,
        entity: HomeAssistantEntity,
        action: HomeAssistantControlAction
    ) -> some View {
        Button {
            perform(entity, action: action)
        } label: {
            Label(title, systemImage: image)
                .font(theme.captionWeightFont)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func perform(_ entity: HomeAssistantEntity, action: HomeAssistantControlAction) {
        do {
            let call = try HomeAssistantControlPolicy.serviceCall(entity: entity, action: action)
            if call.requiresConfirmation {
                confirmation = AccessoryControlConfirmation(call: call)
            } else {
                execute(call)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func execute(_ call: HomeAssistantServiceCall) {
        Task {
            do {
                try await model.execute(call)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct IOSHomeAssistantClimateControlPanel: View {
    let capabilities: HomeAssistantClimateCapabilities
    let symbol: String
    let theme: IOSThemeTokens
    let titleForValue: (String, String) -> String
    let togglePower: (() -> Void)?
    let setTemperature: (Double) -> Void
    let setHVACMode: (String) -> Void
    let setFanMode: (String) -> Void
    let setPresetMode: (String) -> Void
    let setSwingMode: (String) -> Void
    let setHorizontalSwingMode: (String) -> Void

    @State private var draftTemperature: Double
    @State private var isAdjustingTemperature = false

    init(
        capabilities: HomeAssistantClimateCapabilities,
        symbol: String,
        theme: IOSThemeTokens,
        titleForValue: @escaping (String, String) -> String,
        togglePower: (() -> Void)?,
        setTemperature: @escaping (Double) -> Void,
        setHVACMode: @escaping (String) -> Void,
        setFanMode: @escaping (String) -> Void,
        setPresetMode: @escaping (String) -> Void,
        setSwingMode: @escaping (String) -> Void,
        setHorizontalSwingMode: @escaping (String) -> Void
    ) {
        self.capabilities = capabilities
        self.symbol = symbol
        self.theme = theme
        self.titleForValue = titleForValue
        self.togglePower = togglePower
        self.setTemperature = setTemperature
        self.setHVACMode = setHVACMode
        self.setFanMode = setFanMode
        self.setPresetMode = setPresetMode
        self.setSwingMode = setSwingMode
        self.setHorizontalSwingMode = setHorizontalSwingMode
        _draftTemperature = State(initialValue: Self.normalizedTemperature(
            capabilities.targetTemperature
                ?? capabilities.currentTemperature
                ?? capabilities.minimumTemperature,
            capabilities: capabilities
        ))
    }

    var body: some View {
        VStack(spacing: 18) {
            statusHeader

            if capabilities.supportsTargetTemperature {
                temperatureControl
            }

            if capabilities.supportsHVACMode {
                optionSection(
                    title: "运行模式",
                    image: "thermometer.medium",
                    values: capabilities.hvacModes,
                    selected: capabilities.hvacMode,
                    attributeKey: "hvac_modes",
                    action: setHVACMode
                )
            }

            if capabilities.supportsFanMode {
                optionSection(
                    title: "风速",
                    image: "wind",
                    values: capabilities.fanModes,
                    selected: capabilities.fanMode,
                    attributeKey: "fan_mode",
                    action: setFanMode
                )
            }

            if capabilities.supportsSwingMode {
                optionSection(
                    title: capabilities.supportsHorizontalSwingMode ? "上下摆风" : "摆风",
                    image: "arrow.up.and.down",
                    values: capabilities.swingModes,
                    selected: capabilities.swingMode,
                    attributeKey: "swing_mode",
                    action: setSwingMode
                )
            }

            if capabilities.supportsHorizontalSwingMode {
                optionSection(
                    title: "左右摆风",
                    image: "arrow.left.and.right",
                    values: capabilities.horizontalSwingModes,
                    selected: capabilities.horizontalSwingMode,
                    attributeKey: "swing_horizontal_mode",
                    action: setHorizontalSwingMode
                )
            }

            if capabilities.supportsPresetMode {
                optionSection(
                    title: "预设模式",
                    image: "sparkles",
                    values: capabilities.presetModes,
                    selected: capabilities.presetMode,
                    attributeKey: "preset_mode",
                    action: setPresetMode
                )
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: panelShape)
        .background(Color.cyan.opacity(theme.isGeek ? 0.08 : 0.06), in: panelShape)
        .overlay(panelShape.stroke(.white.opacity(0.14), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
        .onChange(of: capabilities.targetTemperature) { _, newValue in
            guard !isAdjustingTemperature, let newValue else { return }
            draftTemperature = Self.normalizedTemperature(newValue, capabilities: capabilities)
        }
    }

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
    }

    private var statusHeader: some View {
        HStack(spacing: 16) {
            Group {
                if let togglePower {
                    Button(action: togglePower) {
                        powerSymbol
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(capabilities.isOn ? "关闭空调" : "开启空调")
                } else {
                    powerSymbol
                        .accessibilityHidden(true)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(capabilities.isOn ? "运行中" : "已关闭")
                    .font(theme.appFont.font(.title2, weight: .semibold))
                    .foregroundStyle(.white)
                if let currentTemperature = capabilities.currentTemperature {
                    Text("室内 \(temperatureText(currentTemperature))")
                        .font(theme.subheadlineWeightFont)
                        .foregroundStyle(.white.opacity(0.62))
                }
            }

            Spacer(minLength: 0)

            if let targetTemperature = capabilities.targetTemperature {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("目标")
                        .font(theme.captionFont)
                        .foregroundStyle(.white.opacity(0.54))
                    Text(temperatureText(targetTemperature))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
            }
        }
    }

    private var powerSymbol: some View {
        ZStack {
            Circle()
                .fill(capabilities.isOn ? Color.cyan : Color.black.opacity(0.20))
            Circle()
                .stroke(.white.opacity(capabilities.isOn ? 0.26 : 0.14), lineWidth: 1)
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(capabilities.isOn ? Color.black.opacity(0.74) : Color.cyan)
        }
        .frame(width: 76, height: 76)
    }

    private var temperatureControl: some View {
        VStack(spacing: 12) {
            HStack {
                Text("目标温度")
                    .font(theme.captionWeightFont)
                    .foregroundStyle(.white.opacity(0.62))
                Spacer()
                Text(temperatureText(draftTemperature))
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }

            HStack(spacing: 12) {
                temperatureButton("minus") {
                    commitTemperature(draftTemperature - capabilities.temperatureStep)
                }

                Slider(
                    value: $draftTemperature,
                    in: capabilities.temperatureRange,
                    step: capabilities.temperatureStep
                ) { editing in
                    isAdjustingTemperature = editing
                    if !editing { setTemperature(draftTemperature) }
                }
                .tint(.cyan)
                .accessibilityLabel("目标温度")
                .accessibilityValue(temperatureText(draftTemperature))

                temperatureButton("plus") {
                    commitTemperature(draftTemperature + capabilities.temperatureStep)
                }
            }
        }
        .padding(16)
        .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func optionSection(
        title: String,
        image: String,
        values: [String],
        selected: String?,
        attributeKey: String,
        action: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: image)
                .font(theme.captionWeightFont)
                .foregroundStyle(.white.opacity(0.64))

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 9) {
                    ForEach(values, id: \.self) { value in
                        let isSelected = value == selected
                        Button {
                            action(value)
                        } label: {
                            Text(titleForValue(attributeKey, value))
                                .font(theme.subheadlineWeightFont)
                                .foregroundStyle(isSelected ? Color.black.opacity(0.78) : Color.white)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 42)
                                .background(
                                    isSelected ? Color.cyan : Color.white.opacity(0.09),
                                    in: Capsule()
                                )
                                .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.75))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
            .contentMargins(.horizontal, 0, for: .scrollContent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func temperatureButton(
        _ image: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Color.white.opacity(0.10), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func commitTemperature(_ value: Double) {
        let normalized = Self.normalizedTemperature(value, capabilities: capabilities)
        draftTemperature = normalized
        setTemperature(normalized)
    }

    private func temperatureText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1))) + capabilities.temperatureUnit
    }

    private static func normalizedTemperature(
        _ value: Double,
        capabilities: HomeAssistantClimateCapabilities
    ) -> Double {
        let clamped = min(capabilities.maximumTemperature, max(capabilities.minimumTemperature, value))
        let step = capabilities.temperatureStep
        let steps = ((clamped - capabilities.minimumTemperature) / step).rounded()
        return min(
            capabilities.maximumTemperature,
            max(capabilities.minimumTemperature, capabilities.minimumTemperature + steps * step)
        )
    }
}

private struct IOSHomeAssistantFanControlPanel: View {
    let isOn: Bool
    let percentage: Double?
    let percentageStep: Double
    let supportsPercentage: Bool
    let presetModes: [String]
    let selectedPresetMode: String?
    let supportsOscillation: Bool
    let isOscillating: Bool?
    let supportsDirection: Bool
    let currentDirection: String?
    let symbol: String
    let theme: IOSThemeTokens
    let titleForPreset: (String) -> String
    let togglePower: () -> Void
    let setPercentage: (Double) -> Void
    let setPresetMode: (String) -> Void
    let setOscillating: (Bool) -> Void
    let setDirection: (String) -> Void

    @State private var draftPercentage: Double
    @State private var isAdjustingPercentage = false

    init(
        isOn: Bool,
        percentage: Double?,
        percentageStep: Double,
        supportsPercentage: Bool,
        presetModes: [String],
        selectedPresetMode: String?,
        supportsOscillation: Bool,
        isOscillating: Bool?,
        supportsDirection: Bool,
        currentDirection: String?,
        symbol: String,
        theme: IOSThemeTokens,
        titleForPreset: @escaping (String) -> String,
        togglePower: @escaping () -> Void,
        setPercentage: @escaping (Double) -> Void,
        setPresetMode: @escaping (String) -> Void,
        setOscillating: @escaping (Bool) -> Void,
        setDirection: @escaping (String) -> Void
    ) {
        self.isOn = isOn
        self.percentage = percentage
        self.percentageStep = percentageStep
        self.supportsPercentage = supportsPercentage
        self.presetModes = presetModes
        self.selectedPresetMode = selectedPresetMode
        self.supportsOscillation = supportsOscillation
        self.isOscillating = isOscillating
        self.supportsDirection = supportsDirection
        self.currentDirection = currentDirection
        self.symbol = symbol
        self.theme = theme
        self.titleForPreset = titleForPreset
        self.togglePower = togglePower
        self.setPercentage = setPercentage
        self.setPresetMode = setPresetMode
        self.setOscillating = setOscillating
        self.setDirection = setDirection
        _draftPercentage = State(
            initialValue: Self.normalizedPercentage(
                percentage ?? 100,
                step: percentageStep
            )
        )
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 22) {
                powerButton
                if supportsPercentage {
                    speedControl
                } else {
                    powerSummary
                }
            }

            if !presetModes.isEmpty {
                presetControl
            }

            if supportsOscillation || supportsDirection {
                HStack(spacing: 10) {
                    if supportsOscillation {
                        featureButton(
                            title: "摆风",
                            subtitle: oscillationSubtitle,
                            image: "fan.oscillation",
                            isActive: isOscillating == true
                        ) {
                            setOscillating(!(isOscillating ?? false))
                        }
                    }

                    if supportsDirection, let nextDirection {
                        featureButton(
                            title: "风向",
                            subtitle: directionTitle(currentDirection),
                            image: "arrow.left.arrow.right",
                            isActive: false
                        ) {
                            setDirection(nextDirection)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: panelShape)
        .background(Color.cyan.opacity(theme.isGeek ? 0.08 : 0.06), in: panelShape)
        .overlay(panelShape.stroke(.white.opacity(0.14), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
        .onChange(of: percentage) { _, newValue in
            guard !isAdjustingPercentage, let newValue else { return }
            draftPercentage = Self.normalizedPercentage(newValue, step: percentageStep)
        }
    }

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
    }

    private var powerButton: some View {
        Button(action: togglePower) {
            ZStack {
                Circle()
                    .fill(isOn ? Color.cyan : Color.white.opacity(0.08))
                Circle()
                    .stroke(.white.opacity(isOn ? 0.28 : 0.14), lineWidth: 1)
                Image(systemName: symbol)
                    .font(.system(size: 45, weight: .semibold))
                    .foregroundStyle(isOn ? Color.black.opacity(0.74) : Color.cyan)
                    .symbolEffect(.variableColor.iterative, options: .nonRepeating, value: isOn)
            }
            .frame(width: 118, height: 118)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "关闭风扇" : "开启风扇")
    }

    private var speedControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("风速")
                .font(theme.captionWeightFont)
                .foregroundStyle(.white.opacity(0.62))
            Text("\(Int(draftPercentage.rounded()))%")
                .font(.system(size: 42, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Slider(
                value: $draftPercentage,
                in: percentageStep...100,
                step: percentageStep
            ) { editing in
                isAdjustingPercentage = editing
                if !editing {
                    setPercentage(draftPercentage)
                }
            }
            .tint(.cyan)
            Text(speedStepText)
                .font(theme.captionFont)
                .foregroundStyle(.white.opacity(0.52))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("风速")
        .accessibilityValue("\(Int(draftPercentage.rounded()))%")
    }

    private var powerSummary: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("电源")
                .font(theme.captionWeightFont)
                .foregroundStyle(.white.opacity(0.62))
            Text(isOn ? "运行中" : "已关闭")
                .font(theme.appFont.font(.title2, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var presetControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("送风模式")
                .font(theme.captionWeightFont)
                .foregroundStyle(.white.opacity(0.62))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(presetModes, id: \.self) { mode in
                        let isSelected = mode == selectedPresetMode
                        Button {
                            setPresetMode(mode)
                        } label: {
                            Text(titleForPreset(mode))
                                .font(theme.subheadlineWeightFont)
                                .foregroundStyle(isSelected ? Color.black.opacity(0.78) : Color.white)
                                .padding(.horizontal, 17)
                                .frame(minHeight: 42)
                                .background(
                                    isSelected ? Color.cyan : Color.white.opacity(0.09),
                                    in: Capsule()
                                )
                                .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.75))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
            .contentMargins(.horizontal, 0, for: .scrollContent)
        }
    }

    private func featureButton(
        title: String,
        subtitle: String,
        image: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: image)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isActive ? Color.black.opacity(0.76) : Color.cyan)
                    .frame(width: 38, height: 38)
                    .background(isActive ? Color.cyan : Color.black.opacity(0.20), in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(theme.subheadlineWeightFont)
                    Text(subtitle)
                        .font(theme.captionFont)
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var oscillationSubtitle: String {
        guard let isOscillating else { return "轻点开启" }
        return isOscillating ? "已开启" : "已关闭"
    }

    private var nextDirection: String? {
        switch currentDirection?.lowercased() {
        case "forward": "reverse"
        case "reverse", "backward": "forward"
        default: nil
        }
    }

    private func directionTitle(_ direction: String?) -> String {
        switch direction?.lowercased() {
        case "forward": "正向"
        case "reverse", "backward": "反向"
        default: "状态未知"
        }
    }

    private var speedStepText: String {
        percentageStep > 1 ? "每档 \(Int(percentageStep.rounded()))%" : "连续调速"
    }

    private static func normalizedPercentage(_ value: Double, step: Double) -> Double {
        let normalizedStep = min(100, max(1, step))
        return min(100, max(normalizedStep, (value / normalizedStep).rounded() * normalizedStep))
    }
}

private struct IOSHomeAssistantVerticalLevelControl: View {
    private let switchThumbInset: CGFloat = 8

    let value: Double
    let isOn: Bool
    let symbol: String
    let accent: Color
    let supportsLevel: Bool
    let isPending: Bool
    let controlWidth: CGFloat
    let controlHeight: CGFloat
    let toggle: () -> Void
    let commit: (Double) -> Void

    @State private var draftValue: Double
    @State private var visualIsOn: Bool
    @State private var switchDragTranslation: CGFloat = 0

    private var cornerRadius: CGFloat {
        controlWidth < 150 ? 42 : 48
    }

    private var iconTapHeight: CGFloat {
        controlWidth < 150 ? 82 : 104
    }

    private var switchThumbHeight: CGFloat {
        controlWidth < 150 ? 116 : 178
    }

    init(
        value: Double,
        isOn: Bool,
        symbol: String,
        accent: Color,
        supportsLevel: Bool,
        isPending: Bool,
        controlWidth: CGFloat,
        controlHeight: CGFloat,
        toggle: @escaping () -> Void,
        commit: @escaping (Double) -> Void
    ) {
        self.value = value
        self.isOn = isOn
        self.symbol = symbol
        self.accent = accent
        self.supportsLevel = supportsLevel
        self.isPending = isPending
        self.controlWidth = controlWidth
        self.controlHeight = controlHeight
        self.toggle = toggle
        self.commit = commit
        _draftValue = State(initialValue: value)
        _visualIsOn = State(initialValue: isOn)
    }

    var body: some View {
        GeometryReader { proxy in
            let normalized = min(1, max(0, draftValue / 100))
            let fillHeight = visualIsOn
                ? max(18, proxy.size.height * normalized)
                : 0
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            let iconUsesDarkForeground = visualIsOn && fillHeight >= iconTapHeight
            let thumbTravel = max(
                0,
                proxy.size.height - switchThumbHeight - switchThumbInset * 2
            )
            let thumbBaseOffset = visualIsOn ? 0 : thumbTravel
            let thumbOffset = switchThumbInset + min(
                thumbTravel,
                max(0, thumbBaseOffset + switchDragTranslation)
            )

            ZStack {
                shape
                    .fill(.thinMaterial)

                shape
                    .fill(.black.opacity(0.34))

                if supportsLevel {
                    ZStack(alignment: .bottom) {
                        Rectangle()
                            .fill(accent)
                            .frame(height: fillHeight)
                            .mask(shape)

                        Image(systemName: symbol)
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(
                                iconUsesDarkForeground
                                    ? .black.opacity(0.72)
                                    : .white.opacity(0.96)
                            )
                            .frame(width: 84, height: iconTapHeight)
                            .contentShape(Rectangle())
                    }
                } else {
                    RoundedRectangle(cornerRadius: 42, style: .continuous)
                        .fill(.black.opacity(0.50))
                        .frame(
                            width: proxy.size.width - switchThumbInset * 2,
                            height: switchThumbHeight
                        )
                        .overlay {
                            Image(systemName: symbol)
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(accent)
                        }
                        .offset(y: thumbOffset - proxy.size.height / 2 + switchThumbHeight / 2)
                        .animation(
                            switchDragTranslation == 0
                                ? .spring(response: 0.32, dampingFraction: 0.82)
                                : nil,
                            value: thumbOffset
                        )
                        .padding(.horizontal, switchThumbInset)
                    }
            }
            .overlay(
                shape
                    .stroke(.white.opacity(0.13), lineWidth: 0.75)
            )
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
            .contentShape(shape)
            .gesture(
                SpatialTapGesture()
                    .onEnded { gesture in
                        if !supportsLevel {
                            toggleOptimistically()
                            return
                        }

                        if gesture.location.y >= proxy.size.height - iconTapHeight {
                            toggleOptimistically()
                            return
                        }

                        let nextValue = level(
                            at: gesture.location.y,
                            height: proxy.size.height
                        )
                        draftValue = nextValue
                        commit(nextValue)
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { gesture in
                        if supportsLevel {
                            draftValue = level(
                                at: gesture.location.y,
                                height: proxy.size.height
                            )
                        } else {
                            switchDragTranslation = gesture.translation.height
                        }
                    }
                    .onEnded { gesture in
                        if supportsLevel {
                            commit(draftValue)
                            return
                        }

                        let projectedOffset = min(
                            thumbTravel,
                            max(
                                0,
                                thumbBaseOffset + gesture.predictedEndTranslation.height
                            )
                        )
                        let shouldTurnOn = projectedOffset < thumbTravel / 2
                        switchDragTranslation = 0
                        if shouldTurnOn != visualIsOn {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                visualIsOn = shouldTurnOn
                            }
                            toggle()
                        }
                    }
            )
        }
        .frame(width: controlWidth, height: controlHeight)
        .onChange(of: value) { _, newValue in
            draftValue = newValue
        }
        .task(id: synchronizationID) {
            guard !isPending else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, visualIsOn != isOn else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                visualIsOn = isOn
            }
        }
        .accessibilityValue(
            supportsLevel
                ? "\(Int(draftValue.rounded()))%"
                : (visualIsOn ? "开启" : "关闭")
        )
        .accessibilityHint(
            supportsLevel
                ? "轻点或上下拖动调整，轻点底部图标开关"
                : "轻点切换开关"
        )
        .accessibilityAdjustableAction { direction in
            guard supportsLevel else {
                toggleOptimistically()
                return
            }

            let step = direction == .increment ? 10.0 : -10.0
            let nextValue = min(100, max(1, draftValue + step))
            draftValue = nextValue
            commit(nextValue)
        }
    }

    private func level(at locationY: CGFloat, height: CGFloat) -> Double {
        min(100, max(1, (1 - locationY / height) * 100))
    }

    private var synchronizationID: String {
        "\(isPending)-\(isOn)-\(visualIsOn)"
    }

    private func toggleOptimistically() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            visualIsOn.toggle()
        }
        toggle()
    }
}

private struct AccessoryControlConfirmation: Identifiable {
    let id = UUID()
    let call: HomeAssistantServiceCall
}
