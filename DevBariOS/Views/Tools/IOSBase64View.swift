import SwiftUI

struct IOSBase64View: View {
    @Environment(\.themeTokens) private var theme
    @State private var input = ""
    @State private var output = ""
    @State private var mode: Base64Mode = .encode

    var body: some View {
        VStack(spacing: 16) {
            Picker("Mode", selection: $mode) {
                ForEach(Base64Mode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            editor(title: "Input", text: $input)

            Button(mode.buttonTitle) {
                transform()
            }
            .buttonStyle(.bordered)
            .disabled(input.isEmpty)

            editor(title: "Output", text: $output)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
            .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("Base64")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .iosToolNavigationChrome(theme)
    }

    private func editor(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            TextEditor(text: text)
                .frame(minHeight: 180)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func transform() {
        switch mode {
        case .encode:
            output = Data(input.utf8).base64EncodedString()
        case .decode:
            guard let data = Data(base64Encoded: input) else {
                output = "Invalid Base64"
                return
            }
            output = String(decoding: data, as: UTF8.self)
        }
    }
}

enum Base64Mode: CaseIterable, Identifiable {
    case encode
    case decode

    var id: String { title }

    var title: String {
        switch self {
        case .encode: return "Encode"
        case .decode: return "Decode"
        }
    }

    var buttonTitle: String {
        switch self {
        case .encode: return "Base64 Encode"
        case .decode: return "Base64 Decode"
        }
    }
}
