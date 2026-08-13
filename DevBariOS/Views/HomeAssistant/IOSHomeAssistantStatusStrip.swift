import SwiftUI

enum IOSHomeAssistantStatusCategory: String, CaseIterable, Identifiable {
    case climate
    case lights
    case security
    case activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .climate: "温控"
        case .lights: "灯"
        case .security: "安全"
        case .activity: "活动"
        }
    }
}

struct IOSHomeAssistantStatusItem: Identifiable, Equatable {
    let category: IOSHomeAssistantStatusCategory
    let title: String
    let detail: String
    let systemImage: String
    let accent: Color

    var id: String { category.id }
}

struct IOSHomeAssistantStatusStrip: View {
    let items: [IOSHomeAssistantStatusItem]
    let selection: IOSHomeAssistantStatusCategory?
    let theme: IOSThemeTokens
    let select: (IOSHomeAssistantStatusCategory) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                ForEach(items) { item in
                    Button {
                        select(item.category)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: item.systemImage)
                                .font(.system(size: 20, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(item.accent)
                                .frame(width: 25)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(theme.appFont.font(.subheadline, weight: .semibold))
                                    .foregroundStyle(primaryTextColor)
                                Text(item.detail)
                                    .font(theme.captionFont)
                                    .foregroundStyle(secondaryTextColor)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(minWidth: 126, minHeight: 54, alignment: .leading)
                        .background {
                            ZStack {
                                Capsule().fill(.ultraThinMaterial)
                                if selection == item.category {
                                    Capsule().fill(selectedFillColor)
                                }
                            }
                        }
                        .overlay(Capsule().stroke(
                            selection == item.category
                                ? item.accent.opacity(0.72)
                                : borderColor,
                            lineWidth: selection == item.category ? 1.5 : 1
                        ))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(selection == item.category ? .isSelected : [])
                }
            }
        }
        .contentMargins(.horizontal, 0, for: .scrollContent)
    }

    private var primaryTextColor: Color {
        theme.isGeek ? theme.textPrimary : .white
    }

    private var secondaryTextColor: Color {
        theme.isGeek ? theme.textSecondary : Color.white.opacity(0.70)
    }

    private var selectedFillColor: Color {
        theme.isGeek ? theme.surfacePrimary.opacity(0.88) : Color.white.opacity(0.18)
    }

    private var borderColor: Color {
        theme.isGeek ? theme.borderSubtle.opacity(0.7) : Color.white.opacity(0.24)
    }
}
