import Foundation

public enum TerminalShortcutKey: String, CaseIterable, Identifiable, Sendable {
    case escape
    case tab
    case controlC
    case controlD
    case arrowUp
    case arrowDown
    case arrowRight
    case arrowLeft
    case controlA
    case controlE
    case controlL
    case clear
    case slash
    case pipe

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .escape:
            return "Esc"
        case .tab:
            return "Tab"
        case .controlC:
            return "Ctrl+C"
        case .controlD:
            return "Ctrl+D"
        case .arrowUp:
            return "Up"
        case .arrowDown:
            return "Down"
        case .arrowRight:
            return "Right"
        case .arrowLeft:
            return "Left"
        case .controlA:
            return "Ctrl+A"
        case .controlE:
            return "Ctrl+E"
        case .controlL:
            return "Ctrl+L"
        case .clear:
            return "Clear"
        case .slash:
            return "/"
        case .pipe:
            return "|"
        }
    }

    public var payload: Data {
        switch self {
        case .escape:
            return Data([0x1B])
        case .tab:
            return Data([0x09])
        case .controlC:
            return Data([0x03])
        case .controlD:
            return Data([0x04])
        case .arrowUp:
            return Data([0x1B, 0x5B, 0x41])
        case .arrowDown:
            return Data([0x1B, 0x5B, 0x42])
        case .arrowRight:
            return Data([0x1B, 0x5B, 0x43])
        case .arrowLeft:
            return Data([0x1B, 0x5B, 0x44])
        case .controlA:
            return Data([0x01])
        case .controlE:
            return Data([0x05])
        case .controlL:
            return Data([0x0C])
        case .clear:
            return Data([0x0C])
        case .slash:
            return Data([0x2F])
        case .pipe:
            return Data([0x7C])
        }
    }
}

public enum TerminalInputControl {
    public static let deleteBackward = Data([0x7F])
}
