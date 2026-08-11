import SwiftUI
import WidgetKit

struct FlipClockEntry: TimelineEntry {
    let date: Date
}

struct FlipClockTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> FlipClockEntry {
        FlipClockEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (FlipClockEntry) -> Void) {
        completion(FlipClockEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FlipClockEntry>) -> Void) {
        completion(timeline(entriesFrom: Date(), makeEntry: FlipClockEntry.init(date:)))
    }

    func timeline<Entry: TimelineEntry>(
        entriesFrom now: Date,
        makeEntry: (Date) -> Entry
    ) -> Timeline<Entry> {
        let refreshDate = now.addingTimeInterval(30 * 60)
        var dates: [Date] = [now]
        var nextDate = now.addingTimeInterval(10)

        while nextDate <= refreshDate {
            dates.append(nextDate)
            nextDate = nextDate.addingTimeInterval(10)
        }

        return Timeline(entries: dates.map(makeEntry), policy: .atEnd)
    }
}

struct FlipClockWidgetView: View {
    let entry: FlipClockEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        GeometryReader { proxy in
            let layout = FlipClockLayout(family: family, size: proxy.size)

            VStack(spacing: layout.verticalSpacing) {
                Spacer(minLength: 0)

                ZStack {
                    HStack(spacing: layout.cardSpacing) {
                        flipCard(text: hourText, layout: layout)
                        flipCard(text: minuteText, layout: layout)
                    }

                    blinkingSeparator(layout: layout)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                dateRow(date: entry.date, layout: layout)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if family == .systemLarge {
                    largeDecoration
                }
            }
            .transaction { transaction in
                transaction.animation = nil
            }
        }
    }

    private func flipCard(text: String, layout: FlipClockLayout) -> some View {
        ZStack {
            flipCardSurface(layout: layout)

            Text(text)
                .font(.system(size: layout.digitSize, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 2)

            flipSeam(layout: layout)
        }
        .frame(width: layout.cardWidth, height: layout.cardHeight)
        .shadow(color: .black.opacity(0.22), radius: layout.cardShadowRadius, y: layout.cardShadowOffset)
    }

    private func flipCardSurface(layout: FlipClockLayout) -> some View {
        let shape = RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)

        return shape
            .fill(.ultraThinMaterial)
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.16, blue: 0.25).opacity(0.76),
                            Color(red: 0.04, green: 0.08, blue: 0.14).opacity(0.84)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .overlay {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.16),
                                    Color.cyan.opacity(0.035),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .black.opacity(0.08),
                                    .black.opacity(0.26)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .clipShape(shape)
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.38),
                            Color.blue.opacity(0.14),
                            .black.opacity(0.32)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
            }
    }

    private func flipSeam(layout: FlipClockLayout) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.black.opacity(0.62))
                .frame(height: layout.seamWidth)
            Rectangle()
                .fill(.white.opacity(0.05))
                .frame(height: 0.35)
        }
        .shadow(color: .black.opacity(0.25), radius: 0.5, y: 0.5)
    }

    private func blinkingSeparator(layout: FlipClockLayout) -> some View {
        TimelineView(.periodic(from: entry.date, by: 1)) { context in
            let isVisible = Calendar.current.component(.second, from: context.date).isMultiple(of: 2)

            Text(":")
                .font(.system(size: layout.digitSize * 0.58, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .opacity(isVisible ? 1 : 0.22)
                .offset(y: -1)
                .shadow(color: .black.opacity(0.42), radius: 1, y: 1)
        }
    }

    private func dateRow(date: Date, layout: FlipClockLayout) -> some View {
        HStack(spacing: layout.dateLineSpacing) {
            dateLine(reversed: false)

            Text(formattedDate(date))
                .font(.system(size: layout.dateSize, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
                .shadow(color: .black.opacity(0.34), radius: 1, y: 1)

            dateLine(reversed: true)
        }
        .frame(maxWidth: layout.dateMaxWidth)
    }

    private func dateLine(reversed: Bool) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: reversed
                        ? [.orange.opacity(0.9), .orange.opacity(0.42), .clear]
                        : [.clear, .orange.opacity(0.42), .orange.opacity(0.9)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(maxWidth: .infinity)
            .frame(height: 1)
    }

    private func formattedDate(_ date: Date) -> String {
        Self.chineseDateFormatter.string(from: date)
    }

    private var largeDecoration: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.2), .clear, .white.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
            .padding(7)
    }

    private var hourText: String {
        String(format: "%02d", Calendar.current.component(.hour, from: entry.date))
    }

    private var minuteText: String {
        String(format: "%02d", Calendar.current.component(.minute, from: entry.date))
    }

    private static let chineseDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()
}

private struct FlipClockLayout {
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let cardSpacing: CGFloat
    let digitSize: CGFloat
    let cornerRadius: CGFloat
    let cardShadowRadius: CGFloat
    let cardShadowOffset: CGFloat
    let seamWidth: CGFloat
    let verticalSpacing: CGFloat
    let dateSize: CGFloat
    let dateLineSpacing: CGFloat
    let dateMaxWidth: CGFloat

    init(family: WidgetFamily, size: CGSize) {
        switch family {
        case .systemLarge:
            let largeCardWidth = min(132, (size.width - 44) / 2)
            cardWidth = largeCardWidth
            cardHeight = min(184, size.height * 0.56)
            cardSpacing = 22
            digitSize = min(92, largeCardWidth * 0.7)
            cornerRadius = 23
            cardShadowRadius = 5
            cardShadowOffset = 4
            seamWidth = 1
            verticalSpacing = 24
            dateSize = 18
            dateLineSpacing = 12
            dateMaxWidth = size.width - 24
        case .systemMedium:
            let mediumCardWidth = min(104, (size.width - 32) / 2)
            cardWidth = mediumCardWidth
            cardHeight = min(102, size.height * 0.66)
            cardSpacing = 16
            digitSize = min(62, mediumCardWidth * 0.64)
            cornerRadius = 17
            cardShadowRadius = 3
            cardShadowOffset = 2
            seamWidth = 0.8
            verticalSpacing = 10
            dateSize = 14
            dateLineSpacing = 8
            dateMaxWidth = size.width - 52
        default:
            let smallCardWidth = min(66, (size.width - 6) / 2)
            cardWidth = smallCardWidth
            cardHeight = min(88, size.height * 0.62)
            cardSpacing = 6
            digitSize = min(48, smallCardWidth * 0.72)
            cornerRadius = 15
            cardShadowRadius = 3
            cardShadowOffset = 2
            seamWidth = 0.7
            verticalSpacing = 11
            dateSize = 12.5
            dateLineSpacing = 5
            dateMaxWidth = size.width - 2
        }
    }
}
