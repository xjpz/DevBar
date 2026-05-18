import SwiftUI

private struct IOSGlassContainerModifier: ViewModifier {
    let theme: IOSThemeTokens
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if theme.isGeek {
            content
                .background {
                    shape
                        .fill(.ultraThinMaterial)
                        .overlay {
                            shape.fill(
                                LinearGradient(
                                    colors: [
                                        theme.surfacePrimary.opacity(0.32),
                                        theme.backgroundSecondary.opacity(0.16),
                                        theme.surfacePrimary.opacity(0.24),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        }
                        .overlay {
                            shape.strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.22),
                                        theme.info.opacity(0.14),
                                        theme.borderSubtle.opacity(0.48),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                        }
                }
                .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
        } else {
            content
                .background(theme.surfacePrimary, in: shape)
        }
    }
}

private struct IOSGeekScreenBackgroundModifier: ViewModifier {
    let theme: IOSThemeTokens

    func body(content: Content) -> some View {
        content
            .background {
                if theme.isGeek {
                    LinearGradient(
                        colors: [
                            theme.backgroundPrimary,
                            theme.backgroundSecondary,
                            theme.backgroundPrimary,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                } else {
                    theme.backgroundSecondary
                        .ignoresSafeArea()
                }
            }
    }
}

extension View {
    func iosGlassContainer(_ theme: IOSThemeTokens, cornerRadius: CGFloat = 18) -> some View {
        modifier(IOSGlassContainerModifier(theme: theme, cornerRadius: cornerRadius))
    }

    func iosGeekScreenBackground(_ theme: IOSThemeTokens) -> some View {
        modifier(IOSGeekScreenBackgroundModifier(theme: theme))
    }
}
