import Foundation

public enum TerminalOutputSanitizer {
    public static func sanitize(_ text: String) -> String {
        var output = ""
        append(text, to: &output)
        return output
    }

    public static func append(_ text: String, to output: inout String) {
        var iterator = text.makeIterator()

        while let character = iterator.next() {
            switch character {
            case "\u{001B}":
                guard let next = iterator.next() else { return }
                switch next {
                case "[":
                    handleCSISequence(&iterator, output: &output)
                case "]":
                    skipOSCSequence(&iterator)
                default:
                    continue
                }
            case "\u{0008}", "\u{007F}":
                removeLastTerminalCharacter(from: &output)
            case "\r\n":
                output.append("\n")
            case "\r":
                continue
            default:
                output.append(character)
            }
        }

        removePromptSetupEchoLines(from: &output)
    }

    private static func handleCSISequence(_ iterator: inout String.Iterator, output: inout String) {
        var sequence = ""
        while let character = iterator.next() {
            sequence.append(character)
            guard let scalar = character.unicodeScalars.first else { continue }
            if scalar.value >= 0x40, scalar.value <= 0x7E {
                if character == "J", shouldClearScreen(sequence) {
                    output.removeAll()
                }
                return
            }
        }
    }

    private static func shouldClearScreen(_ sequence: String) -> Bool {
        sequence == "J" || sequence == "2J" || sequence == "3J"
    }

    private static func skipOSCSequence(_ iterator: inout String.Iterator) {
        while let character = iterator.next() {
            if character == "\u{0007}" {
                return
            }
            if character == "\u{001B}", iterator.next() == "\\" {
                return
            }
        }
    }

    private static func removeLastTerminalCharacter(from output: inout String) {
        guard !output.isEmpty else { return }
        output.removeLast()
    }

    private static func removePromptSetupEchoLines(from output: inout String) {
        let hadTrailingNewline = output.hasSuffix("\n")
        let filteredLines = output
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                !isPromptSetupEchoLine(String(line))
            }

        output = filteredLines.joined(separator: "\n")
        if hadTrailingNewline, !output.hasSuffix("\n") {
            output.append("\n")
        }
    }

    private static func isPromptSetupEchoLine(_ line: String) -> Bool {
        line.contains("setopt PROMPT_SUBST")
            || line.contains("export PS1=")
            || line.contains("export PROMPT=")
            || line.contains("printf '\\033[H\\033[2J'")
            || line.contains("printf '\u{0000}33[H\u{0000}33[2J'")
    }
}
