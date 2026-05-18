import SwiftUI

struct IOSTimestampView: View {
    @Environment(\.themeTokens) private var theme
    @State private var unixInput = ""
    @State private var unixOutput = ""
    @State private var selectedDate = Date()
    @State private var copiedRow: Int?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                toolPanel(title: "Unix Timestamp") {
                    TextField("Seconds or milliseconds", text: $unixInput)
                        .keyboardType(.numbersAndPunctuation)
                        .padding(12)
                        .iosGlassContainer(theme, cornerRadius: 14)

                    Button("Convert to Date") {
                        convertUnix()
                    }
                    .buttonStyle(.bordered)
                    .disabled(unixInput.isEmpty)

                    copyableValueRow(id: 0, title: "Date", value: unixOutput)
                }

                toolPanel(title: "Date to Timestamp") {
                    DatePicker("Select Date", selection: $selectedDate)
                        .datePickerStyle(.graphical)

                    copyableValueRow(id: 1, title: "Format", value: formattedSelectedDate)
                    copyableValueRow(id: 2, title: "Seconds", value: secondsText)
                    copyableValueRow(id: 3, title: "Milliseconds", value: millisecondsText)
                }
            }
            .padding(16)
        }
        .background(Color.clear)
            .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("ios_tools_timestamp")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .iosToolNavigationChrome(theme)
    }

    private func toolPanel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .iosGlassContainer(theme, cornerRadius: 18)
    }

    private func convertUnix() {
        let trimmed = unixInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw = Double(trimmed) else {
            unixOutput = "Invalid timestamp"
            return
        }

        let seconds = trimmed.count > 10 ? raw / 1000 : raw
        let date = Date(timeIntervalSince1970: seconds)
        unixOutput = Self.fullDateFormatter.string(from: date)
    }

    private var formattedSelectedDate: String {
        Self.fullDateFormatter.string(from: selectedDate)
    }

    private var secondsText: String {
        String(Int(selectedDate.timeIntervalSince1970))
    }

    private var millisecondsText: String {
        String(Int(selectedDate.timeIntervalSince1970 * 1000))
    }

    private func copyableValueRow(id: Int, title: String, value: String) -> some View {
        let isCopied = copiedRow == id

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.textSecondary)
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(theme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                UIPasteboard.general.string = value
                withAnimation(.easeOut(duration: 0.25)) {
                    copiedRow = id
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation(.easeOut(duration: 0.25)) {
                        if copiedRow == id { copiedRow = nil }
                    }
                }
            } label: {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.headline)
                    .foregroundStyle(isCopied ? theme.success : theme.brandPrimary)
                    .frame(width: 36, height: 36)
                    .background(theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .disabled(value.isEmpty || value == "Invalid timestamp")
        }
        .padding(12)
        .background(theme.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
