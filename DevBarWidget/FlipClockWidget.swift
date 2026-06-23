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

                HStack(spacing: layout.cardSpacing) {
                    flipCard(text: hourText, layout: layout)
                    flipCard(text: minuteText, layout: layout)
                }

                datePill(date: entry.date, layout: layout)

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
            RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                .fill(.white.opacity(0.14))
                .overlay {
                    RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.24), lineWidth: 0.8)
                }

            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(height: 1)

            Text(text)
                .font(.system(size: layout.digitSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.16), radius: 3, y: 2)
        }
        .frame(width: layout.cardWidth, height: layout.cardHeight)
    }

    private func datePill(date: Date, layout: FlipClockLayout) -> some View {
        Text(formattedDate(date))
            .font(.system(size: layout.dateSize, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.76))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, layout.dateHorizontalPadding)
            .padding(.vertical, layout.dateVerticalPadding)
            .background(.white.opacity(0.08), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.7)
            }
    }

    private func formattedDate(_ date: Date) -> String {
        if family == .systemSmall {
            return Self.smallDateFormatter.string(from: date)
        }
        return date.formatted(.dateTime.month().day().weekday(.wide))
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

    private static let smallDateFormatter: DateFormatter = {
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
    let verticalSpacing: CGFloat
    let dateSize: CGFloat
    let dateHorizontalPadding: CGFloat
    let dateVerticalPadding: CGFloat
    let dateMaxWidth: CGFloat

    init(family: WidgetFamily, size: CGSize) {
        switch family {
        case .systemLarge:
            cardWidth = min(124, (size.width - 52) / 2)
            cardHeight = 132
            cardSpacing = 16
            digitSize = 78
            cornerRadius = 22
            verticalSpacing = 18
            dateSize = 16
            dateHorizontalPadding = 18
            dateVerticalPadding = 7
            dateMaxWidth = size.width - 36
        case .systemMedium:
            cardWidth = min(96, (size.width - 42) / 2)
            cardHeight = 82
            cardSpacing = 14
            digitSize = 54
            cornerRadius = 16
            verticalSpacing = 7
            dateSize = 12
            dateHorizontalPadding = 12
            dateVerticalPadding = 3
            dateMaxWidth = size.width - 80
        default:
            cardWidth = min(58, (size.width - 18) / 2)
            cardHeight = 68
            cardSpacing = 8
            digitSize = 38
            cornerRadius = 13
            verticalSpacing = 10
            dateSize = 10
            dateHorizontalPadding = 10
            dateVerticalPadding = 4
            dateMaxWidth = size.width - 14
        }
    }
}
