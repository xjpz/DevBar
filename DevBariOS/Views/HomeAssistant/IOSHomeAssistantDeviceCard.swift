import DevBarCore
import Foundation
import SwiftUI

struct IOSHomeAssistantDeviceCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let accessory: HomeAssistantAccessory
    let state: HomeAssistantAccessorySemanticState
    let size: HomeAssistantCardSize
    let isPending: Bool
    let controlsEnabled: Bool
    let isEditing: Bool
    let theme: IOSThemeTokens
    let open: () -> Void
    let edit: () -> Void
    let quickAction: () -> Void
    let toggleSize: () -> Void
    let hide: () -> Void
    let beginLayoutEditing: (() -> Void)?

    var body: some View {
        Group {
            if size == .compact {
                compactContent
            } else {
                standardContent
            }
        }
        .padding(size == .compact ? 8 : 12)
        .frame(maxWidth: .infinity, minHeight: size.dashboardHeight, maxHeight: size.dashboardHeight, alignment: .leading)
        .background { cardBackground }
        .overlay(cardShape.stroke(cardBorderColor, lineWidth: 0.8))
        .shadow(color: cardShadowColor, radius: cardShadowRadius, y: cardShadowOffset)
        .overlay(alignment: .topTrailing) {
            if isEditing { editControls.padding(6) }
        }
        .contentShape(cardShape)
        .onTapGesture {
            if !isEditing { open() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "编辑设备", edit)
        .accessibilityValue(accessibilityStateText)
        .contextMenu {
            deviceContextMenu
                .transaction { transaction in
                    transaction.animation = nil
                }
        }
    }

    private var compactContent: some View {
        HStack(spacing: 10) {
            iconButton(diameter: 40, symbolSize: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(accessory.name)
                    .font(theme.appFont.font(.subheadline, weight: .semibold))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                Text(state.primaryText)
                    .font(theme.captionFont)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
            Spacer(minLength: isEditing ? 48 : 0)
        }
    }

    private var standardContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top) {
                iconButton(diameter: 42, symbolSize: 19)
                Spacer(minLength: isEditing ? 52 : 0)
                if !isEditing, let currentIndoorTemperatureText {
                    Text(currentIndoorTemperatureText)
                        .font(theme.appFont.font(.largeTitle, weight: .bold).monospacedDigit())
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                if accessory.needsReview, !isEditing {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(theme.warning)
                        .padding(5)
                        .background(.regularMaterial, in: Circle())
                        .accessibilityLabel("需要整理")
                }
            }
            Spacer(minLength: 2)
            Text(accessory.name)
                .font(theme.appFont.font(.headline, weight: .semibold))
                .foregroundStyle(titleColor)
                .lineLimit(2)
            Text(state.primaryText)
                .font(theme.subheadlineFont)
                .foregroundStyle(statusColor)
                .lineLimit(1)
        }
    }

    private func iconButton(diameter: CGFloat, symbolSize: CGFloat) -> some View {
        Button(action: iconAction) {
            ZStack {
                Circle()
                    .fill(iconPlateColor)
                    .frame(width: diameter, height: diameter)
                Image(systemName: accessory.systemImage)
                    .font(.system(size: symbolSize, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(iconForegroundColor)
            }
        }
        .buttonStyle(.plain)
        .disabled(isEditing)
        .accessibilityLabel(hasQuickAction ? "控制 \(accessory.name)" : "查看 \(accessory.name)")
        .accessibilityValue(isPending ? "\(state.primaryText)，正在执行" : state.primaryText)
    }

    private var editControls: some View {
        HStack(spacing: 6) {
            Button(action: toggleSize) {
                Image(systemName: size == .compact
                    ? "arrow.up.left.and.arrow.down.right"
                    : "arrow.down.right.and.arrow.up.left")
            }
            Image(systemName: "line.3.horizontal")
                .accessibilityLabel("拖动以重新排序")
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(titleColor)
        .padding(.horizontal, 7)
        .frame(minHeight: 26)
        .background(.regularMaterial, in: Capsule())
    }

    @ViewBuilder
    private var deviceContextMenu: some View {
        if !isEditing {
            Button(action: edit) {
                Label("配件设置", systemImage: "gearshape")
            }
            Button(role: .destructive, action: hide) {
                Label("从家庭视图中移除", systemImage: "minus.circle")
            }
            if let beginLayoutEditing {
                Divider()
                Button(action: beginLayoutEditing) {
                    Label("编辑家庭视图", systemImage: "square.grid.2x2")
                }
            }
        }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size == .compact ? 18 : 22, style: .continuous)
    }

    private var cardBackground: some View {
        ZStack {
            cardShape.fill(.ultraThinMaterial)
            cardShape.fill(cardFillColor)
            cardShape.fill(
                LinearGradient(
                    colors: cardHighlightColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    private var cardFillColor: Color {
        switch presentationState {
        case .on:
            return Color.white.opacity(colorScheme == .dark ? 0.90 : 0.96)
        case .off:
            if theme.isGeek { return theme.surfacePrimary.opacity(0.74) }
            return colorScheme == .dark
                ? theme.surfaceSecondary.opacity(0.82)
                : Color.black.opacity(0.48)
        case .warning:
            return theme.warning.opacity(theme.isGeek ? 0.18 : 0.13)
        case .unavailable:
            return theme.surfaceSecondary.opacity(theme.isGeek ? 0.42 : 0.52)
        case .neutral:
            return theme.surfacePrimary.opacity(theme.isGeek ? 0.58 : (colorScheme == .dark ? 0.68 : 0.72))
        }
    }

    private var cardHighlightColors: [Color] {
        switch presentationState {
        case .on:
            return [Color.white.opacity(0.22), accentColor.opacity(0.07), .clear]
        case .off:
            return [Color.white.opacity(0.08), .clear, Color.black.opacity(0.08)]
        case .warning:
            return [Color.white.opacity(0.10), theme.warning.opacity(0.08), .clear]
        case .unavailable, .neutral:
            return [Color.white.opacity(0.10), .clear, theme.surfaceSecondary.opacity(0.08)]
        }
    }

    private var cardBorderColor: Color {
        switch presentationState {
        case .on: Color.white.opacity(0.52)
        case .off: Color.white.opacity(0.13)
        case .warning: theme.warning.opacity(0.32)
        case .unavailable, .neutral: theme.borderSubtle.opacity(0.55)
        }
    }

    private var cardShadowColor: Color {
        switch presentationState {
        case .on: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.10)
        case .off: Color.black.opacity(0.08)
        case .warning: theme.warning.opacity(0.08)
        case .unavailable, .neutral: Color.black.opacity(0.035)
        }
    }

    private var cardShadowRadius: CGFloat {
        presentationState == .on ? 8 : 4
    }

    private var cardShadowOffset: CGFloat {
        presentationState == .on ? 4 : 2
    }

    private var hasQuickAction: Bool {
        guard let entity = accessory.quickControlEntity else { return false }
        return entity.isAvailable && HomeAssistantControlPolicy.quickAction(for: entity) != nil
    }

    private var currentIndoorTemperatureText: String? {
        guard accessory.kind == .airConditioner, let temperature = state.currentTemperature else {
            return nil
        }
        return "\(temperature.formatted(.number.precision(.fractionLength(0...1))))°"
    }

    private var accessibilityStateText: String {
        let temperatureText = currentIndoorTemperatureText.map { "室内温度 \($0)" }
        return [temperatureText, state.primaryText, state.secondaryText]
            .compactMap { $0 }
            .joined(separator: "，")
    }

    private func iconAction() {
        guard !isPending else { return }
        if hasQuickAction && controlsEnabled { quickAction() } else { open() }
    }

    private var presentationState: CardPresentationState {
        if state.tone == .warning { return .warning }
        if state.tone == .unavailable { return .unavailable }
        switch state.power {
        case .on: return .on
        case .off, .standby: return .off
        case .notApplicable, .unknown: return .neutral
        }
    }

    private var accentColor: Color {
        switch accessory.kind {
        case .light, .switchDevice: theme.warning
        case .fan, .airConditioner: theme.info
        case .airPurifier: theme.brandPrimary
        case .sensorGroup: theme.textSecondary
        case .generic: theme.brandPrimary
        }
    }

    private var iconPlateColor: Color {
        switch presentationState {
        case .on: accentColor
        case .off: Color.black.opacity(colorScheme == .dark ? 0.24 : 0.16)
        case .warning: theme.warning.opacity(0.20)
        case .unavailable: theme.textTertiary.opacity(0.13)
        case .neutral: theme.textPrimary.opacity(colorScheme == .dark ? 0.12 : 0.08)
        }
    }

    private var iconForegroundColor: Color {
        switch presentationState {
        case .on: Color.black.opacity(0.78)
        case .off: accentColor
        case .warning: theme.warning
        case .unavailable: theme.textTertiary
        case .neutral: theme.textSecondary
        }
    }

    private var titleColor: Color {
        switch presentationState {
        case .on: Color.black.opacity(0.90)
        case .off: Color.white.opacity(0.96)
        case .warning, .neutral: theme.textPrimary
        case .unavailable: theme.textTertiary
        }
    }

    private var statusColor: Color {
        switch presentationState {
        case .on: Color.black.opacity(0.55)
        case .off: Color.white.opacity(0.68)
        case .warning: theme.warning
        case .unavailable: theme.textTertiary
        case .neutral: theme.textSecondary
        }
    }
}

private enum CardPresentationState: Equatable {
    case on
    case off
    case warning
    case unavailable
    case neutral
}

struct IOSHomeAssistantPageBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(IOSHomeAssistantWallpaper.storageKey) private var selectedWallpaperRawValue =
        IOSHomeAssistantWallpaper.blueMist.rawValue

    let theme: IOSThemeTokens
    var wallpaper: IOSHomeAssistantWallpaper? = nil

    private var resolvedWallpaper: IOSHomeAssistantWallpaper {
        wallpaper ?? IOSHomeAssistantWallpaper(rawValue: selectedWallpaperRawValue) ?? .blueMist
    }

    private var wallpaperOverlayOpacity: Double {
        let baseOpacity = resolvedWallpaper.overlayOpacity(for: colorScheme)
        return min(baseOpacity + (theme.isGeek ? 0.14 : 0), 0.58)
    }

    var body: some View {
        GeometryReader { proxy in
            Image(resolvedWallpaper.assetName)
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .overlay {
                    Color.black.opacity(wallpaperOverlayOpacity)
                }
                .overlay {
                    if theme.isGeek {
                        theme.heroGradient.opacity(0.14)
                    }
                }
        }
        .background {
            if theme.isGeek {
                Color.black
            } else {
                Color(red: 0.39, green: 0.50, blue: 0.67)
            }
        }
    }
}

extension View {
    func homeAssistantTransparentNavigationBar() -> some View {
        toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.clear, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

enum IOSHomeAssistantCardMetrics {
    static let spacing: CGFloat = 10
}

extension HomeAssistantCardSize {
    var dashboardHeight: CGFloat {
        switch self {
        case .compact: 64
        case .standard: 138
        }
    }
}
