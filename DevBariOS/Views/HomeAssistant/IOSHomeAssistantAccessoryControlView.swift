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

                Spacer(minLength: controlProjection.usesChildControlGrid ? 0 : 8)
                controlSurface
                    .disabled(!model.canControlDevices || isPending)
                if controlProjection.usesChildControlGrid {
                    childControlGrid
                }
                auxiliaryControls
                Spacer(minLength: controlProjection.usesChildControlGrid ? 0 : 8)
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
        liveAccessory.entities.contains { model.pendingEntityIDs.contains($0.entityID) }
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
            glassCircleButton("xmark", diameter: 48) {
                dismiss()
            }
            .accessibilityLabel("关闭")

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
                levelControl(
                    entity: entity,
                    value: fanLevel(entity),
                    symbol: liveAccessory.systemImage,
                    accent: .cyan,
                    supportsLevel: entity.state.attributes["percentage"] != nil,
                    compact: controlProjection.usesChildControlGrid,
                    levelAction: { .setPercentage($0) }
                )
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
        let current = entity.state.attributes["current_temperature"]?.doubleValue
        let target = entity.state.attributes["temperature"]?.doubleValue ?? current ?? 22
        return VStack(spacing: 22) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.18), lineWidth: 28)
                Circle()
                    .trim(from: 0.08, to: 0.82)
                    .stroke(
                        Color.cyan,
                        style: StrokeStyle(lineWidth: 28, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))

                VStack(spacing: 5) {
                    Text(target.formatted(.number.precision(.fractionLength(0...1))) + "°")
                        .font(.system(size: 58, weight: .medium))
                        .foregroundStyle(.white)
                    if let current {
                        Text("当前 \(current.formatted(.number.precision(.fractionLength(0...1))))°")
                            .font(theme.subheadlineWeightFont)
                            .foregroundStyle(.white.opacity(0.62))
                    }
                }
            }
            .frame(width: 250, height: 250)

            HStack(spacing: 28) {
                roundActionButton("minus") {
                    perform(entity, action: .setTemperature(max(10, target - 0.5)))
                }
                roundActionButton("plus") {
                    perform(entity, action: .setTemperature(min(35, target + 0.5)))
                }
            }

            climateModeMenu(entity)
        }
    }

    private func climateModeMenu(_ entity: HomeAssistantEntity) -> some View {
        Menu {
            ForEach(entity.state.attributes["hvac_modes"]?.arrayValue?.compactMap(\.stringValue) ?? [], id: \.self) { mode in
                Button(HomeAssistantStateFormatter.translatedState(
                    mode,
                    domain: "climate",
                    deviceClass: nil,
                    role: nil
                )) {
                    perform(entity, action: .setHVACMode(mode))
                }
            }
        } label: {
            HStack {
                Text(model.stateText(for: entity))
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
            }
            .font(theme.appFont.font(.headline, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .frame(maxWidth: 300, minHeight: 58)
            .background(.ultraThinMaterial, in: Capsule())
        }
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(auxiliary) { entity in
                        Button {
                            if let action = HomeAssistantControlPolicy.quickAction(for: entity) {
                                perform(entity, action: action)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.displayName(for: entity))
                                    .font(theme.captionWeightFont)
                                    .lineLimit(1)
                                Text(model.stateText(for: entity))
                                    .font(theme.captionFont)
                                    .foregroundStyle(.white.opacity(0.58))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(minWidth: 112, minHeight: 52, alignment: .leading)
                            .background(.ultraThinMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(
                            !model.canControlDevices
                                || !entity.isAvailable
                                || model.pendingEntityIDs.contains(entity.entityID)
                                || HomeAssistantControlPolicy.quickAction(for: entity) == nil
                        )
                    }
                }
            }
            .contentMargins(.horizontal, 0, for: .scrollContent)
        }
    }

    private var auxiliaryControlEntities: [HomeAssistantEntity] {
        let roles: [HomeAssistantAccessoryRole] = [.power, .childControl, .indicator, .action]
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

    private func fanLevel(_ entity: HomeAssistantEntity) -> Double {
        guard entity.isOn else { return 0 }
        return entity.state.attributes["percentage"]?.doubleValue ?? 100
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
