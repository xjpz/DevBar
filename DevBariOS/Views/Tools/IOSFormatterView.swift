import SwiftUI

struct IOSFormatterView: View {
    @Environment(\.themeTokens) private var theme
    @State private var input = "{\n\"hello\":\"world\"\n}"
    @State private var output = ""

    var body: some View {
        VStack(spacing: 16) {
            formatterEditor(title: "Input", text: $input)

            HStack {
                Button("Pretty Print") {
                    formatJSON(pretty: true)
                }
                .buttonStyle(.bordered)
                .disabled(input.isEmpty)

                Button("Compact") {
                    formatJSON(pretty: false)
                }
                .buttonStyle(.bordered)
            }

            formatterEditor(title: "Output", text: $output)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.backgroundSecondary.ignoresSafeArea())
        .navigationTitle("ios_tools_formatter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private func formatterEditor(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 220)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .foregroundStyle(theme.textPrimary)
    }

    private func formatJSON(pretty: Bool) {
        guard let data = input.data(using: .utf8) else {
            output = "Invalid input"
            return
        }

        do {
            let object = try JSONSerialization.jsonObject(with: data)
            let options: JSONSerialization.WritingOptions = pretty ? [.prettyPrinted] : []
            let formatted = try JSONSerialization.data(withJSONObject: object, options: options)
            output = String(decoding: formatted, as: UTF8.self)
        } catch {
            output = error.localizedDescription
        }
    }
}
