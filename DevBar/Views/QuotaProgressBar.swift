import SwiftUI

enum QuotaProgressBand: Equatable {
    case normal
    case warning
    case critical

    init(percentage: Int) {
        switch percentage {
        case ..<50:
            self = .normal
        case 50..<80:
            self = .warning
        default:
            self = .critical
        }
    }

    var color: Color {
        switch self {
        case .normal:
            return .green
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }
}

struct QuotaProgressBar: View {
    let percentage: Int

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.secondary.opacity(0.2))

                Capsule()
                    .fill(QuotaProgressBand(percentage: percentage).color)
                    .frame(width: geometry.size.width * progress)
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel(
            Text(String(format: String(localized: "used_percentage"), clampedPercentage))
        )
    }

    var clampedPercentage: Int {
        min(max(percentage, 0), 100)
    }

    private var progress: CGFloat {
        CGFloat(clampedPercentage) / 100
    }
}
