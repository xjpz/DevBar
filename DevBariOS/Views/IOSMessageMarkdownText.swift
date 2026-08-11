import DevBarCore
import SwiftUI

struct IOSMessageMarkdownText: View {
    enum Syntax {
        case full
        case inline
    }

    let source: String
    var syntax: Syntax = .full

    @ViewBuilder
    var body: some View {
        switch syntax {
        case .full:
            IOSMessageMarkdownBlocks(source: source)
        case .inline:
            Text(IOSMessageMarkdownParser.inline(source))
        }
    }
}

private struct IOSMessageMarkdownBlocks: View {
    let source: String

    private var blocks: [IOSMessageMarkdownBlock] {
        IOSMessageMarkdownParser.blocks(source)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks) { block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: IOSMessageMarkdownBlock) -> some View {
        switch block.kind {
        case let .heading(level, content):
            Text(IOSMessageMarkdownParser.inline(content))
                .font(headingFont(level))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

        case let .paragraph(content):
            Text(IOSMessageMarkdownParser.inline(content))
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

        case let .bullet(content):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .font(.body.weight(.semibold))
                Text(IOSMessageMarkdownParser.inline(content))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.primary)

        case let .numbered(marker, content):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                    .font(.body.monospacedDigit().weight(.semibold))
                Text(IOSMessageMarkdownParser.inline(content))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.primary)

        case let .quote(content):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.accentColor.opacity(0.55))
                    .frame(width: 3)
                Text(IOSMessageMarkdownParser.inline(content))
                    .font(.body.italic())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 3)

        case let .code(content):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(content)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

        case .divider:
            Divider()
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title.bold()
        case 2: .title2.bold()
        case 3: .title3.bold()
        default: .headline
        }
    }
}

private struct IOSMessageMarkdownBlock: Identifiable {
    enum Kind {
        case heading(level: Int, content: String)
        case paragraph(String)
        case bullet(String)
        case numbered(marker: String, content: String)
        case quote(String)
        case code(String)
        case divider
    }

    let id: Int
    let kind: Kind
}

private enum IOSMessageMarkdownParser {
    static func inline(_ source: String) -> AttributedString {
        let parsed = try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )
        return sanitizeLinks(in: parsed ?? AttributedString(source))
    }

    static func blocks(_ source: String) -> [IOSMessageMarkdownBlock] {
        let lines = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var result: [IOSMessageMarkdownBlock] = []
        var paragraphLines: [String] = []
        var index = 0

        func append(_ kind: IOSMessageMarkdownBlock.Kind) {
            result.append(IOSMessageMarkdownBlock(id: result.count, kind: kind))
        }

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            append(.paragraph(paragraphLines.joined(separator: "\n")))
            paragraphLines.removeAll(keepingCapacity: true)
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                flushParagraph()
                var codeLines: [String] = []
                index += 1
                while index < lines.count,
                      !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                append(.code(codeLines.joined(separator: "\n")))
                continue
            }

            if let heading = heading(from: trimmed) {
                flushParagraph()
                append(.heading(level: heading.level, content: heading.content))
                index += 1
                continue
            }

            if isDivider(trimmed) {
                flushParagraph()
                append(.divider)
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoteLines: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    quoteLines.append(String(candidate.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                append(.quote(quoteLines.joined(separator: "\n")))
                continue
            }

            if let bullet = bulletContent(from: trimmed),
               let heading = heading(from: bullet) {
                flushParagraph()
                append(.heading(level: heading.level, content: heading.content))
                index += 1
                continue
            }

            if let bullet = bulletContent(from: trimmed) {
                flushParagraph()
                append(.bullet(bullet))
                index += 1
                continue
            }

            if let numbered = numberedContent(from: trimmed) {
                flushParagraph()
                append(.numbered(marker: numbered.marker, content: numbered.content))
                index += 1
                continue
            }

            paragraphLines.append(line)
            index += 1
        }

        flushParagraph()
        if result.isEmpty {
            append(.paragraph(source))
        }
        return result
    }

    private static func heading(from line: String) -> (level: Int, content: String)? {
        let level = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level),
              line.dropFirst(level).first == " " else {
            return nil
        }
        return (level, String(line.dropFirst(level + 1)))
    }

    private static func bulletContent(from line: String) -> String? {
        guard line.count >= 2 else { return nil }
        let prefix = line.prefix(2)
        guard prefix == "- " || prefix == "* " || prefix == "+ " || prefix == "• " else { return nil }
        return String(line.dropFirst(2))
    }

    private static func numberedContent(from line: String) -> (marker: String, content: String)? {
        guard let separator = line.firstIndex(where: { $0 == "." || $0 == ")" }) else { return nil }
        let number = line[..<separator]
        guard !number.isEmpty,
              number.allSatisfy(\.isNumber) else {
            return nil
        }
        let afterSeparator = line.index(after: separator)
        guard afterSeparator < line.endIndex,
              line[afterSeparator] == " " else {
            return nil
        }
        return (
            String(line[...separator]),
            String(line[line.index(after: afterSeparator)...])
        )
    }

    private static func isDivider(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3, let marker = compact.first else { return false }
        return (marker == "-" || marker == "*" || marker == "_") && compact.allSatisfy { $0 == marker }
    }

    private static func sanitizeLinks(in value: AttributedString) -> AttributedString {
        var result = value
        let unsafeRanges = result.runs.compactMap { run -> Range<AttributedString.Index>? in
            guard let link = run.link,
                  PushNotificationURLPolicy.validatedURL(from: link.absoluteString) == nil else {
                return nil
            }
            return run.range
        }
        for range in unsafeRanges {
            result[range].link = nil
        }
        return result
    }
}
