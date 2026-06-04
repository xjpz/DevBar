import SwiftUI
import WidgetKit

enum WidgetVisualStyle: String, CaseIterable {
    case transparent
    case liquidGlass
    case dark

    var title: String {
        switch self {
        case .transparent: return "透明"
        case .liquidGlass: return "液态玻璃"
        case .dark: return "深色"
        }
    }

    var widgetDisplayName: String {
        switch self {
        case .transparent: return "透明小组件"
        case .liquidGlass: return "液态玻璃小组件"
        case .dark: return "深色小组件"
        }
    }
}

struct WidgetVisualStyleBackground: View {
    let style: WidgetVisualStyle

    var body: some View {
        switch style {
        case .transparent:
            Color.clear
        case .liquidGlass:
            liquidGlassBackground
        case .dark:
            Color(red: 0.055, green: 0.065, blue: 0.085)
        }
    }

    @ViewBuilder
    private var liquidGlassBackground: some View {
        customLiquidGlassBackground
    }

    private var customLiquidGlassBackground: some View {
        ContainerRelativeShape()
            .fill(
                LinearGradient(
                    colors: [
                        .white.opacity(0.028),
                        .cyan.opacity(0.012),
                        .black.opacity(0.01)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                ContainerRelativeShape()
                    .fill(
                        RadialGradient(
                            colors: [
                                .white.opacity(0.042),
                                .clear
                            ],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 220
                        )
                    )
            }
            .overlay {
                ContainerRelativeShape()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.26),
                                .white.opacity(0.045),
                                .white.opacity(0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            }
    }
}

extension View {
    func styledWidgetBackground(_ style: WidgetVisualStyle) -> some View {
        containerBackground(for: .widget) {
            WidgetVisualStyleBackground(style: style)
        }
    }
}
