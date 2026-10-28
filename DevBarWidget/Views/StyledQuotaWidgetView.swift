#if os(iOS)
import DevBarCore
import SwiftUI
import WidgetKit

struct StyledQuotaWidgetView: View {
    let entry: QuotaEntry
    let visualStyle: WidgetVisualStyle
    let appearance: QuotaWidgetAppearance

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsContainerBackground
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var isSmall: Bool { family == .systemSmall }
    private var palette: QuotaInstrumentPalette {
        QuotaInstrumentPalette(
            visualStyle: visualStyle, textSelection: appearance.text,
            renderingMode: renderingMode, colorScheme: colorScheme,
            increasedContrast: contrast == .increased, reduceTransparency: reduceTransparency,
            showsContainerBackground: showsContainerBackground,
            instrumentStyle: appearance.style
        )
    }
    private var limit: WidgetQuotaLimit? {
        WidgetQuotaPresentation.selectedLimit(
            in: entry.data.limits, provider: entry.data.provider, period: appearance.period.period
        )
    }
    private var providerTitle: String {
        (entry.data.provider.flatMap { WidgetProviderSelection(rawValue: $0.rawValue) }
            ?? entry.selectedProvider).displayName
    }
    private var stale: Bool {
        entry.isLoggedIn && entry.date.timeIntervalSince(entry.data.lastUpdated) > 60 * 60
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isSmall ? 5 : 10) {
            header
            if !entry.isLoggedIn {
                emptyState("widget_not_logged_in")
            } else if entry.data.limits.isEmpty {
                emptyState("quota_instrument_waiting")
            } else if let limit {
                if family == .systemMedium {
                    HStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            cycleLabel(limit)
                            Text("\(limit.percentage)%")
                                .font(.system(size: 38, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .minimumScaleFactor(0.65)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        instrument(limit, showsLabel: false)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    instrument(limit, showsLabel: true)
                        .frame(maxHeight: .infinity, alignment: isSmall && appearance.style.isInstrument ? .bottom : .center)
                    if family == .systemLarge { otherLimits(excluding: limit) }
                }
                footer(limit)
            } else {
                emptyState("quota_instrument_missing_period")
            }
        }
        .padding(isSmall ? 4 : 6)
        .foregroundStyle(palette.primary)
        .background(palette.backing, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: palette.shadow, radius: 1, y: 0.5)
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            headerRow(showsIcon: true)
            headerRow(showsIcon: false)
        }
        .font(.system(size: isSmall ? 11 : 13, weight: .semibold))
    }

    private func headerRow(showsIcon: Bool) -> some View {
        HStack(spacing: 4) {
            if showsIcon {
                providerIcon.accessibilityHidden(true)
            }
            Text(providerTitle)
                .fontWeight(appearance.style.isInstrument ? .medium : .bold)
                .foregroundStyle(appearance.style == .led ? palette.secondary : palette.primary)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 2)
            if let count = entry.data.availableResetCount, count > 0 {
                HStack(spacing: 1) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("\(count)").monospacedDigit()
                }
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 3)
                .padding(.vertical, 2)
                .overlay(Capsule().strokeBorder(palette.border, lineWidth: 0.8))
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("quota_instrument_resets \(count)"))
            }
            if entry.data.lastUpdated != .distantPast {
                HStack(spacing: 2) {
                    Image(systemName: stale ? "exclamationmark.clock" : "arrow.clockwise")
                    Text(entry.data.lastUpdated, format: .dateTime.hour().minute()).monospacedDigit()
                }
                .foregroundStyle(palette.secondary)
                .font(.system(size: 9, weight: .medium))
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("quota_instrument_updated \(entry.data.lastUpdated.formatted(date: .abbreviated, time: .shortened))"))
            }
        }
    }

    @ViewBuilder
    private var providerIcon: some View {
        if appearance.style.isInstrument, entry.selectedProvider == .openai {
            // This existing asset is a white mark on opaque black; template mode
            // would turn its entire rectangular bitmap into a solid square.
            (appearance.style == .led ? palette.secondary : palette.primary)
                .frame(width: 12, height: 12)
                .mask {
                    Image("OpenAI")
                        .resizable()
                        .scaledToFit()
                        .luminanceToAlpha()
                }
        } else {
            Image(systemName: "chart.pie.fill")
        }
    }

    private func cycleLabel(_ limit: WidgetQuotaLimit) -> some View {
        Text(cycleTitle(limit))
            .font(.system(size: isSmall ? 11 : 13, weight: .semibold))
            .foregroundStyle(palette.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private func cycleTitle(_ limit: WidgetQuotaLimit) -> String {
        if WidgetQuotaPresentation.isFiveHourLimit(limit) { return String(localized: "5 小时") }
        if WidgetQuotaPresentation.isWeeklyLimit(limit) { return String(localized: "每周") }
        if WidgetQuotaPresentation.isMonthlyLimit(limit) { return String(localized: "每月") }
        return limit.displayName
    }

    @ViewBuilder
    private func instrument(_ limit: WidgetQuotaLimit, showsLabel: Bool) -> some View {
        let percentage = min(max(limit.percentage, 0), 100)
        VStack(alignment: .leading, spacing: appearance.style.isInstrument ? (isSmall ? 7 : 9) : (isSmall ? 5 : 8)) {
            if appearance.style == .github {
                if showsLabel {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(limit.percentage)%")
                            .font(.system(size: isSmall ? 29 : 44, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        cycleLabel(limit)
                    }
                }
                QuotaContributionGrid(percentage: percentage, palette: palette)
                    .frame(maxHeight: family == .systemLarge ? 140 : 82)
                if family == .systemLarge {
                    Text("quota_instrument_used")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(palette.secondary)
                }
            } else {
                if showsLabel { cycleLabel(limit) }
                instrumentDigits(percentage, height: isSmall ? 36 : 62)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(Text("quota_instrument_percentage \(limit.percentage)"))
                QuotaSegmentProgress(
                    percentage: percentage, round: appearance.style == .led, palette: palette,
                    height: isSmall ? (appearance.style == .led ? 7 : 12) : 12
                )
                .padding(.top, isSmall ? 3 : 5)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("quota_instrument_summary \(cycleTitle(limit)) \(limit.percentage)"))
    }

    @ViewBuilder
    private func instrumentDigits(_ percentage: Int, height: CGFloat) -> some View {
        GeometryReader { geometry in
            let text = "\(percentage)%"
            let widthRatio = appearance.style == .led
                ? QuotaDotMatrix(text: text).aspectRatio
                : QuotaSevenSegment(text: String(percentage)).aspectRatio + 0.56
            let fittedHeight = min(height, geometry.size.width / widthRatio)
            instrumentDigitShapes(percentage, height: fittedHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: height)
    }

    @ViewBuilder
    private func instrumentDigitShapes(_ percentage: Int, height: CGFloat) -> some View {
        if appearance.style == .led {
            let text = "\(percentage)%"
            ZStack {
                QuotaDotMatrix(text: text, lit: false).fill(palette.unlit)
                QuotaDotMatrix(text: text).fill(palette.accent).widgetAccentable()
            }
            .frame(width: QuotaDotMatrix(text: text).aspectRatio * height, height: height)
        } else {
            let digits = String(percentage)
            HStack(alignment: .bottom, spacing: 4) {
                ZStack {
                    QuotaSevenSegment(text: digits, lit: false).fill(palette.unlit)
                    QuotaSevenSegment(text: digits).fill(palette.primary)
                }
                .frame(width: QuotaSevenSegment(text: digits).aspectRatio * height, height: height)
                Text("%")
                    .font(.system(size: height * 0.48, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func footer(_ limit: WidgetQuotaLimit) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if stale {
                Text("quota_instrument_cached")
                    .font(.system(size: 10, weight: .semibold))
            }
            if let reset = QuotaWidgetResetPresentation.text(for: limit.formattedResetTime, at: entry.date) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) {
                        Text("quota_instrument_reset")
                        Spacer(minLength: 0)
                        Text(reset).monospacedDigit()
                            .foregroundStyle(appearance.style == .led ? palette.accent : palette.primary)
                    }
                    Text(reset).monospacedDigit()
                }
                .accessibilityLabel(Text("quota_instrument_reset_at \(reset)"))
            } else {
                Text("quota_instrument_used")
            }
        }
        .font(.system(size: isSmall ? 10 : 12, weight: .medium))
        .foregroundStyle(palette.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func otherLimits(excluding primary: WidgetQuotaLimit) -> some View {
        VStack(spacing: 7) {
            ForEach(Array(WidgetQuotaPresentation.sortedLimits(entry.data.limits, provider: entry.data.provider)
                .filter { $0.id != primary.id }.prefix(2))) { other in
                HStack {
                    cycleLabel(other)
                    Spacer()
                    Text("\(other.percentage)%").monospacedDigit().fontWeight(.bold)
                }
                .font(.caption)
            }
        }
    }

    private func emptyState(_ key: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title2)
                .accessibilityHidden(true)
            Text(key).font(.callout.weight(.semibold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
#endif
