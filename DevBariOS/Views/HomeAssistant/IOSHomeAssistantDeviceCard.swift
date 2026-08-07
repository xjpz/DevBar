import DevBarCore
import SwiftUI

struct IOSHomeAssistantDeviceCard: View {
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
        .background(.ultraThinMaterial, in: cardShape)
        .background(cardTint, in: cardShape)
        .overlay(cardShape.stroke(theme.borderSubtle.opacity(0.72), lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            if isEditing { editControls.padding(6) }
        }
        .contentShape(cardShape)
        .onTapGesture {
            if !isEditing { open() }
        }
        .contextMenu {
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
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "编辑设备", edit)
        .accessibilityValue([state.primaryText, state.secondaryText].compactMap { $0 }.joined(separator: "，"))
    }

    private var compactContent: some View {
        HStack(spacing: 10) {
            iconButton(diameter: 40, symbolSize: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(accessory.name)
                    .font(theme.appFont.font(.subheadline, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text(state.primaryText)
                    .font(theme.captionFont)
                    .foregroundStyle(state.tone == .active ? iconColor : theme.textSecondary)
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
                if accessory.needsReview, !isEditing {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(theme.warning)
                        .accessibilityLabel("需要整理")
                }
            }
            Spacer(minLength: 2)
            Text(accessory.name)
                .font(theme.appFont.font(.headline, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(2)
            Text(state.primaryText)
                .font(theme.subheadlineFont)
                .foregroundStyle(state.tone == .active ? iconColor : theme.textSecondary)
                .lineLimit(1)
        }
    }

    private func iconButton(diameter: CGFloat, symbolSize: CGFloat) -> some View {
        Button(action: iconAction) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(state.power == .on ? 0.22 : 0.13))
                    .frame(width: diameter, height: diameter)
                if isPending {
                    ProgressView().tint(iconColor)
                } else {
                    Image(systemName: accessory.systemImage)
                        .font(.system(size: symbolSize, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isEditing || accessory.quickControlEntity == nil || isPending)
        .accessibilityLabel(hasQuickAction ? "控制 \(accessory.name)" : "查看 \(accessory.name)")
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
        .foregroundStyle(theme.textPrimary)
        .padding(.horizontal, 7)
        .frame(minHeight: 26)
        .background(.regularMaterial, in: Capsule())
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size == .compact ? 18 : 22, style: .continuous)
    }

    private var cardTint: Color {
        switch state.tone {
        case .active:
            return theme.surfacePrimary.opacity(theme.isGeek ? 0.62 : 0.96)
        case .warning:
            return theme.warning.opacity(theme.isGeek ? 0.12 : 0.08)
        case .unavailable:
            return theme.surfaceSecondary.opacity(0.44)
        case .neutral:
            return theme.surfaceSecondary.opacity(theme.isGeek ? 0.32 : 0.72)
        }
    }

    private var hasQuickAction: Bool {
        guard let entity = accessory.quickControlEntity else { return false }
        return entity.isAvailable && HomeAssistantControlPolicy.quickAction(for: entity) != nil
    }

    private func iconAction() {
        if hasQuickAction && controlsEnabled { quickAction() } else { open() }
    }

    private var iconColor: Color {
        switch state.tone {
        case .active:
            return accessory.kind == .light ? theme.warning : theme.brandPrimary
        case .warning: return theme.warning
        case .unavailable: return theme.textTertiary
        case .neutral:
            return theme.textPrimary.opacity(theme.isGeek ? 0.72 : 0.62)
        }
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
