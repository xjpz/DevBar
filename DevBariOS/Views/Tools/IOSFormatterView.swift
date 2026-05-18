import SwiftUI

// MARK: - Types

enum FormatterFormat: String, CaseIterable, Identifiable {
    case json, xml, url, jwt, html

    var id: String { rawValue }

    var title: String {
        switch self {
        case .json: "JSON"
        case .xml: "XML"
        case .url: "URL"
        case .jwt: "JWT"
        case .html: "HTML"
        }
    }

    var operations: [FormatterOp] {
        switch self {
        case .json: [.prettyPrint, .compact]
        case .xml: [.prettyPrint, .compact]
        case .url: [.encode, .decode]
        case .jwt: [.decode]
        case .html: [.format, .minify]
        }
    }

    var sampleInput: String {
        switch self {
        case .json:
            "{\"name\":\"DevBar\",\"version\":1,\"features\":[\"quota\",\"tools\"]}"
        case .xml:
            "<root><name>DevBar</name><version>1</version></root>"
        case .url:
            "https://example.com/api?q=hello world&lang=中文"
        case .jwt:
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        case .html:
            "<div><h1>Title</h1><p>Hello <em>world</em></p></div>"
        }
    }
}

enum FormatterOp: String, CaseIterable, Identifiable {
    case prettyPrint, compact, encode, decode, format, minify

    var id: String { rawValue }

    var title: String {
        switch self {
        case .prettyPrint: String(localized: "ios_tools_formatter_pretty_print")
        case .compact: String(localized: "ios_tools_formatter_compact")
        case .encode: String(localized: "ios_tools_formatter_encode")
        case .decode: String(localized: "ios_tools_formatter_decode")
        case .format: String(localized: "ios_tools_formatter_format")
        case .minify: String(localized: "ios_tools_formatter_minify")
        }
    }
}

// MARK: - View

struct IOSFormatterView: View {
    @Environment(\.themeTokens) private var theme
    @State private var format: FormatterFormat = .json
    @State private var input = "{\"name\":\"DevBar\",\"version\":1,\"features\":[\"quota\",\"tools\"]}"
    @State private var output = ""
    @State private var isKeyboardVisible = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !isKeyboardVisible {
                    VStack(spacing: 16) {
                        Picker("Format", selection: $format) {
                            ForEach(FormatterFormat.allCases) { fmt in
                                Text(fmt.title).tag(fmt)
                            }
                        }
                        .pickerStyle(.segmented)

                        HStack {
                            ForEach(format.operations) { op in
                                Button(op.title) {
                                    perform(op)
                                }
                                .buttonStyle(.bordered)
                                .disabled(input.isEmpty)
                            }
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                formatterEditor(title: String(localized: "ios_tools_formatter_input"), text: $input)

                outputEditor(title: String(localized: "ios_tools_formatter_output"), text: output)
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.clear)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("ios_tools_formatter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .iosToolNavigationChrome(theme)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.25)) { isKeyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.25)) { isKeyboardVisible = false }
        }
        .onChange(of: format) { _, newFormat in
            input = newFormat.sampleInput
            output = ""
        }
    }

    private func formatterEditor(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 180)
                .scrollContentBackground(.hidden)
                .padding(12)
                .iosGlassContainer(theme, cornerRadius: 18)
        }
        .foregroundStyle(theme.textPrimary)
    }

    private func outputEditor(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            TextEditor(text: .constant(text))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 180)
                .scrollContentBackground(.hidden)
                .padding(12)
                .iosGlassContainer(theme, cornerRadius: 18)
                .disabled(true)
        }
        .foregroundStyle(theme.textPrimary)
    }

    // MARK: - Operations

    private func perform(_ op: FormatterOp) {
        switch format {
        case .json:
            formatJSON(pretty: op == .prettyPrint)
        case .xml:
            formatXML(pretty: op == .prettyPrint)
        case .url:
            if op == .encode { urlEncode() } else { urlDecode() }
        case .jwt:
            decodeJWT()
        case .html:
            if op == .format { formatHTML() } else { minifyHTML() }
        }
    }

    // MARK: JSON

    private func formatJSON(pretty: Bool) {
        guard let data = input.data(using: .utf8) else {
            output = String(localized: "ios_tools_formatter_invalid_input")
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

    // MARK: XML

    private func formatXML(pretty: Bool) {
        if pretty {
            formatXMLPretty()
        } else {
            output = input
                .replacingOccurrences(of: ">\\s+<", with: "><", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func formatXMLPretty() {
        let minified = input
            .replacingOccurrences(of: ">\\s+<", with: "><", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var result = ""
        var indent = 0

        let pattern = "(<[^>]+>)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            output = minified
            return
        }

        let range = NSRange(minified.startIndex..., in: minified)
        let matches = regex.matches(in: minified, range: range)

        var lastEnd = minified.startIndex
        for match in matches {
            if let tagNSRange = Range(match.range, in: minified) {
                if lastEnd < tagNSRange.lowerBound {
                    let text = String(minified[lastEnd..<tagNSRange.lowerBound])
                        .trimmingCharacters(in: .whitespaces)
                    if !text.isEmpty {
                        result += String(repeating: "  ", count: indent) + text + "\n"
                    }
                }

                let tag = String(minified[tagNSRange])

                if tag.hasPrefix("</") {
                    indent = max(0, indent - 1)
                    result += String(repeating: "  ", count: indent) + tag + "\n"
                } else if tag.hasPrefix("<?") || tag.hasPrefix("<!") || tag.hasSuffix("/>") {
                    result += String(repeating: "  ", count: indent) + tag + "\n"
                } else {
                    result += String(repeating: "  ", count: indent) + tag + "\n"
                    indent += 1
                }

                lastEnd = tagNSRange.upperBound
            }
        }

        if lastEnd < minified.endIndex {
            let trailing = String(minified[lastEnd...]).trimmingCharacters(in: .whitespaces)
            if !trailing.isEmpty {
                result += String(repeating: "  ", count: max(0, indent - 1)) + trailing + "\n"
            }
        }

        output = result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: URL

    private func urlEncode() {
        output = input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input
    }

    private func urlDecode() {
        output = input.removingPercentEncoding ?? input
    }

    // MARK: JWT

    private func decodeJWT() {
        let parts = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: ".")
        guard parts.count >= 2 else {
            output = String(localized: "ios_tools_formatter_invalid_input")
            return
        }

        var result = ""

        if let headerData = base64URLDecode(parts[0]),
           let headerStr = prettyJSON(from: headerData) {
            result += "Header:\n\(headerStr)"
        } else {
            result += "Header: (decode failed)"
        }

        result += "\n\n"

        if let payloadData = base64URLDecode(parts[1]),
           let payloadStr = prettyJSON(from: payloadData) {
            result += "Payload:\n\(payloadStr)"
        } else {
            result += "Payload: (decode failed)"
        }

        if parts.count >= 3 {
            result += "\n\nSignature: \(parts[2].prefix(20))..."
        }

        output = result
    }

    private func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = base64.count % 4
        if padding > 0 {
            base64 += String(repeating: "=", count: 4 - padding)
        }
        return Data(base64Encoded: base64)
    }

    private func prettyJSON(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let formatted = try? JSONSerialization.data(withJSONObject: object, options: .prettyPrinted)
        else { return nil }
        return String(decoding: formatted, as: UTF8.self)
    }

    // MARK: HTML

    private func formatHTML() {
        let minified = input
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        var result = ""
        var indent = 0
        let selfClosing = Set(["br", "hr", "img", "input", "meta", "link", "area", "base", "col", "embed", "source", "track", "wbr"])

        // Split on tags
        let pattern = "(<[^>]+>)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            output = minified
            return
        }

        let range = NSRange(minified.startIndex..., in: minified)
        let matches = regex.matches(in: minified, range: range)

        var lastEnd = minified.startIndex
        for match in matches {
            if let tagNSRange = Range(match.range, in: minified) {
                // Text before tag
                if lastEnd < tagNSRange.lowerBound {
                    let text = String(minified[lastEnd..<tagNSRange.lowerBound])
                        .trimmingCharacters(in: .whitespaces)
                    if !text.isEmpty {
                        result += String(repeating: "  ", count: indent) + text + "\n"
                    }
                }

                let tag = String(minified[tagNSRange])

                if tag.hasPrefix("</") {
                    indent = max(0, indent - 1)
                    result += String(repeating: "  ", count: indent) + tag + "\n"
                } else if tag.hasPrefix("<") && !tag.hasSuffix("/>") {
                    result += String(repeating: "  ", count: indent) + tag + "\n"
                    let tagName = tag.dropFirst().split(separator: " ").first?.description ?? ""
                    let name = tagName.split(separator: ">").first?.description ?? tagName
                    if !selfClosing.contains(name) && !tag.contains("<!--") {
                        indent += 1
                    }
                } else {
                    result += String(repeating: "  ", count: indent) + tag + "\n"
                }

                lastEnd = tagNSRange.upperBound
            }
        }

        // Trailing text
        if lastEnd < minified.endIndex {
            let trailing = String(minified[lastEnd...]).trimmingCharacters(in: .whitespaces)
            if !trailing.isEmpty {
                result += String(repeating: "  ", count: indent) + trailing + "\n"
            }
        }

        output = result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func minifyHTML() {
        output = input
            .replacingOccurrences(of: ">\\s+<", with: "><", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
