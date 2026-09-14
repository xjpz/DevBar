import SwiftUI

struct IOSHomeAssistantColorTemperatureControl: View {
    let initialValue: Double?
    let range: ClosedRange<Double>
    let theme: IOSThemeTokens
    let usesDarkSurface: Bool
    let commit: (Double) -> Void

    @State private var value: Double
    @State private var isEditing = false

    init(
        initialValue: Double?,
        range: ClosedRange<Double>,
        theme: IOSThemeTokens,
        usesDarkSurface: Bool,
        commit: @escaping (Double) -> Void
    ) {
        self.initialValue = initialValue
        self.range = range
        self.theme = theme
        self.usesDarkSurface = usesDarkSurface
        self.commit = commit
        _value = State(initialValue: Self.normalized(initialValue, in: range))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("色温", systemImage: "thermometer.medium")
                Spacer()
                Text("\(Int(value.rounded())) K")
                    .contentTransition(.numericText())
            }
            .font(theme.captionWeightFont)
            .foregroundStyle(primaryColor)

            Slider(value: $value, in: range, step: 1) { editing in
                isEditing = editing
                if !editing { commit(value.rounded()) }
            }
            .tint(.orange)
            .accessibilityLabel("色温")
            .accessibilityValue("\(Int(value.rounded())) 开尔文")
        }
        .padding(usesDarkSurface ? 14 : 0)
        .background {
            if usesDarkSurface {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.orange.opacity(theme.isGeek ? 0.08 : 0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(.white.opacity(0.14), lineWidth: 0.75)
                    )
            }
        }
        .onChange(of: initialValue) { _, newValue in
            guard !isEditing else { return }
            value = Self.normalized(newValue, in: range)
        }
        .onChange(of: range) { _, newRange in
            guard !isEditing else { return }
            value = Self.normalized(initialValue, in: newRange)
        }
    }

    private var primaryColor: Color {
        usesDarkSurface ? .white : theme.textPrimary
    }

    private static func normalized(
        _ value: Double?,
        in range: ClosedRange<Double>
    ) -> Double {
        let fallback = (range.lowerBound + range.upperBound) / 2
        return min(range.upperBound, max(range.lowerBound, value ?? fallback))
    }
}
