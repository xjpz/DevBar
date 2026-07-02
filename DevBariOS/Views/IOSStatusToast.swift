import SwiftUI

enum IOSStatusToastKind: Equatable {
    case success
    case failure

    func iconColor(theme: IOSThemeTokens) -> Color {
        switch self {
        case .success:
            return theme.brandPrimary
        case .failure:
            return theme.danger
        }
    }

    var systemImage: String {
        switch self {
        case .success:
            return "checkmark"
        case .failure:
            return "xmark"
        }
    }
}

struct IOSStatusToast: View {
    let title: String
    let kind: IOSStatusToastKind
    let theme: IOSThemeTokens

    init(_ title: String, kind: IOSStatusToastKind, theme: IOSThemeTokens) {
        self.title = title
        self.kind = kind
        self.theme = theme
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(kind.iconColor(theme: theme))
                .frame(height: 48)

            Text(title)
                .font(theme.bodyFont.weight(.semibold))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(width: 164, height: 126)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(theme.borderSubtle.opacity(theme.isGeek ? 0.34 : 0.18), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(theme.isGeek ? 0.28 : 0.14), radius: 18, y: 10)
    }
}
