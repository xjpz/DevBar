import DevBarCore
import SwiftUI
import UIKit

struct IOSTerminalSessionView: View {
    @Environment(\.themeTokens) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel: IOSTerminalSessionViewModel
    @State private var isKeyboardFocused = false

    init(server: IOSTerminalServer) {
        _viewModel = StateObject(wrappedValue: IOSTerminalSessionRegistry.shared.session(for: server))
    }

    var body: some View {
        VStack(spacing: 0) {
            terminalOutput
        }
        .background(terminalScreenBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            controlsDock
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 6)
                .onChanged { _ in
                    isKeyboardFocused = false
                }
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .iosToolNavigationChrome(theme, showsBackButton: true)
        .toolbar {
            ToolbarItem(placement: .principal) {
                terminalToolbarTitle
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.reconnect()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .iosToolToolbarIcon(theme)
                }
                .accessibilityLabel("Reconnect")
            }
        }
        .onAppear {
            viewModel.connect()
        }
        .accessibilityIdentifier("ios.tools.terminal.session")
    }

    private var terminalToolbarTitle: some View {
        VStack(spacing: 5) {
            Text("Terminal")
                .font(theme.appFont.font(.headline, weight: .semibold, monospaced: theme.isGeek))
                .foregroundStyle(theme.textPrimary)
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(statusTitle)
                    .font(theme.captionWeightFont)
                    .foregroundStyle(statusTextColor)
                    .lineLimit(1)
            }
            .frame(maxWidth: 190)
        }
        .accessibilityElement(children: .combine)
    }

    private var controlsDock: some View {
        ZStack {
            IOSTerminalShortcutBar(isEnabled: viewModel.canSendInput) { shortcut in
                if shortcut == .clear {
                    viewModel.clearOutput()
                }
                viewModel.sendShortcut(shortcut)
            }
            hiddenKeyboardInput
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(terminalControlsBackground)
    }

    private var terminalScreenBackground: Color {
        usesDarkTerminalCanvas ? .black : theme.backgroundSecondary
    }

    private var terminalBackground: Color {
        usesDarkTerminalCanvas ? .black : theme.backgroundSecondary
    }

    private var terminalControlsBackground: Color {
        usesDarkTerminalCanvas ? .black : theme.backgroundSecondary
    }

    private var usesDarkTerminalCanvas: Bool {
        theme.isGeek || colorScheme == .dark
    }

    private var terminalOutput: some View {
        ScrollViewReader { proxy in
            ScrollView {
                TimelineView(.periodic(from: .now, by: 0.55)) { context in
                    Text(terminalDisplayText(at: context.date))
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.green.opacity(0.92))
                        .lineSpacing(1)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(12)
                        .id("terminal-output-bottom")
                }
            }
            .background(terminalBackground)
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .onTapGesture {
                if viewModel.canSendInput {
                    isKeyboardFocused = true
                }
            }
            .onChange(of: viewModel.output) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("terminal-output-bottom", anchor: .bottom)
                }
            }
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            updateTerminalViewport(geometry.size)
                        }
                        .onChange(of: geometry.size) { _, size in
                            updateTerminalViewport(size)
                        }
                }
            }
        }
    }

    private func terminalDisplayText(at date: Date) -> String {
        let output = viewModel.output.isEmpty ? "$" : viewModel.output
        guard viewModel.canSendInput else {
            return output
        }

        let cursorVisible = Int(date.timeIntervalSinceReferenceDate / 0.55).isMultiple(of: 2)
        return output + (cursorVisible ? "▌" : " ")
    }

    private var hiddenKeyboardInput: some View {
        TerminalKeyboardCaptureView(
            isFocused: $isKeyboardFocused,
            isEnabled: viewModel.canSendInput,
            onText: { text in
                viewModel.sendText(text)
            },
            onReturn: {
                viewModel.sendReturn()
            },
            onDeleteBackward: {
                viewModel.sendDeleteBackward()
            }
        )
        .frame(width: 1, height: 1)
        .opacity(0.01)
    }

    private var statusColor: Color {
        switch viewModel.state {
        case .connected:
            return theme.success
        case .connecting:
            return theme.warning
        case .disconnected:
            return theme.textTertiary
        case .failed:
            return theme.danger
        }
    }

    private func updateTerminalViewport(_ size: CGSize) {
        let columns = TerminalViewportCalculator.columns(forWidth: size.width)
        let rows = TerminalViewportCalculator.rows(forHeight: size.height)
        viewModel.updateViewport(columns: columns, rows: rows)
    }

    private var statusTitle: String {
        switch viewModel.state {
        case let .failed(message):
            return message.isEmpty ? viewModel.state.title : "\(viewModel.state.title): \(message)"
        default:
            return viewModel.state.title
        }
    }

    private var statusTextColor: Color {
        switch viewModel.state {
        case .failed:
            return theme.danger
        default:
            return theme.textSecondary
        }
    }
}

private struct TerminalKeyboardCaptureView: UIViewRepresentable {
    @Binding var isFocused: Bool
    let isEnabled: Bool
    let onText: (String) -> Void
    let onReturn: () -> Void
    let onDeleteBackward: () -> Void

    func makeUIView(context: Context) -> TerminalKeyboardInputView {
        let inputView = TerminalKeyboardInputView(frame: .zero)
        inputView.backgroundColor = .clear
        return inputView
    }

    func updateUIView(_ uiView: TerminalKeyboardInputView, context: Context) {
        uiView.isEnabledForInput = isEnabled
        uiView.onText = onText
        uiView.onReturn = onReturn
        uiView.onDeleteBackward = onDeleteBackward
        uiView.onFocusChanged = { isFocused in
            guard self.isFocused != isFocused else { return }
            DispatchQueue.main.async {
                self.isFocused = isFocused
            }
        }

        let shouldFocus = isFocused && isEnabled
        DispatchQueue.main.async {
            if shouldFocus, !uiView.isFirstResponder {
                _ = uiView.becomeFirstResponder()
            } else if !shouldFocus, uiView.isFirstResponder {
                _ = uiView.resignFirstResponder()
            }
        }
    }
}

private final class TerminalKeyboardInputView: UIView, UIKeyInput, UITextInputTraits {
    var isEnabledForInput = false {
        didSet {
            if !isEnabledForInput, isFirstResponder {
                _ = resignFirstResponder()
            }
        }
    }

    var onText: ((String) -> Void)?
    var onReturn: (() -> Void)?
    var onDeleteBackward: (() -> Void)?
    var onFocusChanged: ((Bool) -> Void)?

    var autocapitalizationType: UITextAutocapitalizationType = .none
    var autocorrectionType: UITextAutocorrectionType = .no
    var spellCheckingType: UITextSpellCheckingType = .no
    var smartDashesType: UITextSmartDashesType = .no
    var smartQuotesType: UITextSmartQuotesType = .no
    var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
    var keyboardType: UIKeyboardType = .asciiCapable
    var keyboardAppearance: UIKeyboardAppearance = .dark
    var returnKeyType: UIReturnKeyType = .default
    var enablesReturnKeyAutomatically = false

    override var canBecomeFirstResponder: Bool {
        isEnabledForInput
    }

    var hasText: Bool {
        true
    }

    func insertText(_ text: String) {
        guard isEnabledForInput else { return }
        if text == "\n" || text == "\r" {
            onReturn?()
        } else {
            onText?(text)
        }
    }

    func deleteBackward() {
        guard isEnabledForInput else { return }
        onDeleteBackward?()
    }

    override func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        if didBecome {
            onFocusChanged?(true)
        }
        return didBecome
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign {
            onFocusChanged?(false)
        }
        return didResign
    }
}

struct IOSTerminalShortcutBar: View {
    let isEnabled: Bool
    let send: (TerminalShortcutKey) -> Void

    private let shortcuts: [TerminalShortcutKey] = [
        .escape,
        .tab,
        .controlC,
        .controlD,
        .arrowUp,
        .arrowDown,
        .arrowLeft,
        .arrowRight,
        .clear,
        .slash,
        .pipe,
        .controlA,
        .controlE,
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(shortcuts) { shortcut in
                    Button {
                        send(shortcut)
                    } label: {
                        shortcutLabel(shortcut)
                            .foregroundStyle(isEnabled ? Color.white.opacity(0.88) : Color.white.opacity(0.32))
                            .frame(minWidth: shortcut.compactIconName == nil ? 52 : 42, minHeight: 32)
                            .background(
                                Color.white.opacity(isEnabled ? 0.12 : 0.07),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEnabled)
                    .accessibilityLabel(shortcut.title)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func shortcutLabel(_ shortcut: TerminalShortcutKey) -> some View {
        if let iconName = shortcut.compactIconName {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
        } else {
            Text(shortcut.title)
                .font(.caption.weight(.medium).monospaced())
        }
    }
}

private extension TerminalShortcutKey {
    var compactIconName: String? {
        switch self {
        case .arrowUp:
            return "arrow.up"
        case .arrowDown:
            return "arrow.down"
        case .arrowLeft:
            return "arrow.left"
        case .arrowRight:
            return "arrow.right"
        case .clear:
            return "eraser.fill"
        default:
            return nil
        }
    }
}
