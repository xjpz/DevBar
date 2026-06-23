import DevBarCore
import SwiftUI
import UIKit

struct IOSHermesChatView: View {
    @EnvironmentObject private var appViewModel: IOSAppViewModel
    @Environment(\.themeTokens) private var theme
    @StateObject private var viewModel = IOSHermesChatViewModel()

    var body: some View {
        ZStack {
            Color.clear
                .iosGeekScreenBackground(theme)

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 10)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            memoryBanner

                            if !viewModel.isConfigured {
                                missingConfigCard
                            } else if viewModel.messages.isEmpty {
                                emptyPrompts
                            }

                            ForEach(viewModel.messages) { message in
                                HermesMessageBubble(
                                    message: message,
                                    retry: viewModel.retryLastPrompt,
                                    theme: theme
                                )
                                .id(message.id)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 18)
                    }
                    .onChange(of: viewModel.messages) { _, messages in
                        guard let lastID = messages.last?.id else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            composer
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(theme.backgroundPrimary.opacity(0.96))
        }
        .onAppear {
            configureViewModel()
        }
        .onChange(of: appViewModel.hermesSettings) { _, _ in
            configureViewModel()
        }
        .onChange(of: appViewModel.hermesSettingsRevision) { _, _ in
            configureViewModel()
        }
        .accessibilityIdentifier("ios.hermes.chat.screen")
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "line.3.horizontal")
                .font(.title2.weight(.medium))
                .foregroundStyle(theme.textPrimary)

            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.18))
                    .frame(width: 52, height: 52)
                Image(systemName: "sparkles")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.purple)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Hermes Chat")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)

                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.isConfigured ? Color.green : Color.orange)
                        .frame(width: 9, height: 9)
                    Text(viewModel.isConfigured ? "ios_hermes_agent_online" : "ios_hermes_not_configured")
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                }
            }

            Spacer()

            Button {} label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3.weight(.semibold))
            }
            .disabled(true)
            .foregroundStyle(theme.textSecondary)

            Button {} label: {
                Image(systemName: "ellipsis")
                    .font(.title3.weight(.semibold))
            }
            .disabled(true)
            .foregroundStyle(theme.textSecondary)
        }
    }

    private var memoryBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.purple)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text("ios_hermes_memory_enabled")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                Text("ios_hermes_memory_detail")
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
            }

            Spacer()

            Button("ios_hermes_view_memory") {}
                .buttonStyle(.bordered)
                .tint(.purple)
                .disabled(true)
        }
        .padding(16)
        .iosGlassContainer(theme, cornerRadius: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(theme.borderSubtle, lineWidth: 1)
        )
    }

    private var missingConfigCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("ios_hermes_missing_config_title", systemImage: "key")
                .font(.headline.weight(.semibold))
                .foregroundStyle(theme.textPrimary)

            Text("ios_hermes_missing_config_detail")
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)

            NavigationLink {
                IOSSettingsView()
            } label: {
                Label("ios_hermes_open_settings", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .iosGlassContainer(theme, cornerRadius: 16)
    }

    private var emptyPrompts: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ios_hermes_prompt_suggestions")
                .font(.headline.weight(.semibold))
                .foregroundStyle(theme.textPrimary)

            ForEach(promptSuggestions, id: \.self) { prompt in
                Button {
                    viewModel.draft = prompt
                } label: {
                    HStack {
                        Text(prompt)
                            .foregroundStyle(theme.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(.purple)
                    }
                    .padding(12)
                    .background(theme.backgroundSecondary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .iosGlassContainer(theme, cornerRadius: 16)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Button {} label: {
                Image(systemName: "paperclip")
                    .font(.title2.weight(.semibold))
                    .frame(width: 34, height: 34)
            }
            .disabled(true)
            .foregroundStyle(theme.textSecondary)

            TextField(String(localized: "ios_hermes_input_hint"), text: $viewModel.draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(.vertical, 12)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled(false)
                .accessibilityIdentifier("ios.hermes.chat.input")

            Button {
                if viewModel.isBusy {
                    viewModel.cancel()
                } else {
                    viewModel.sendDraft()
                }
            } label: {
                Image(systemName: viewModel.isBusy ? "stop.fill" : "paperplane.fill")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(
                        Circle()
                            .fill(viewModel.canSend || viewModel.isBusy ? Color.purple : theme.textTertiary.opacity(0.35))
                    )
            }
            .disabled(!viewModel.canSend && !viewModel.isBusy)
            .accessibilityIdentifier("ios.hermes.chat.send")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .iosGlassContainer(theme, cornerRadius: 18)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(theme.borderSubtle, lineWidth: 1)
        )
    }

    private func configureViewModel() {
        viewModel.configure(
            settings: appViewModel.hermesSettings,
            apiKey: appViewModel.hermesAPIKey
        )
    }

    private var promptSuggestions: [String] {
        [
            String(localized: "ios_hermes_prompt_check_deploy"),
            String(localized: "ios_hermes_prompt_summarize_context"),
            String(localized: "ios_hermes_prompt_create_plan"),
        ]
    }
}

private struct HermesMessageBubble: View {
    let message: IOSHermesChatViewModel.Message
    let retry: () -> Void
    let theme: IOSThemeTokens

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 64)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(message.content)
                        .font(.body)
                        .foregroundStyle(.white)
                    Text(Self.timeFormatter.string(from: message.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.68))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.88), Color.blue.opacity(0.82)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.purple)
                        .frame(width: 34, height: 34)
                        .background(Color.purple.opacity(0.16), in: Circle())

                    Text("Hermes Agent")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.purple)

                    Text(Self.timeFormatter.string(from: message.createdAt))
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)

                    Spacer()
                }

                if message.content.isEmpty && !message.isComplete {
                    ProgressView()
                        .tint(.purple)
                } else {
                    HermesMessageContent(content: message.content, theme: theme)
                }

                if case .assistant = message.role, message.isComplete {
                    HStack(spacing: 10) {
                        Button {
                            UIPasteboard.general.string = message.content
                        } label: {
                            Label("ios_common_copy", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        .tint(.purple)

                        Button {
                            retry()
                        } label: {
                            Label("ios_hermes_regenerate", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .tint(.purple)
                    }
                    .font(.caption.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .iosGlassContainer(theme, cornerRadius: 16)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(theme.borderSubtle, lineWidth: 1)
            )
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private struct HermesMessageContent: View {
    let content: String
    let theme: IOSThemeTokens

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let text):
                    Text(text)
                        .font(.body)
                        .foregroundStyle(theme.textPrimary)
                        .textSelection(.enabled)
                case .code(let language, let code):
                    HermesCodeBlock(language: language, code: code, theme: theme)
                }
            }
        }
    }

    private var blocks: [HermesRenderedBlock] {
        let parts = content.components(separatedBy: "```")
        var result: [HermesRenderedBlock] = []

        for index in parts.indices {
            let part = parts[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !part.isEmpty else { continue }

            if index.isMultiple(of: 2) {
                result.append(.text(part))
            } else {
                let lines = part.components(separatedBy: .newlines)
                let firstLine = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if lines.count > 1, !firstLine.isEmpty, firstLine.range(of: #"^[A-Za-z0-9_+-]+$"#, options: .regularExpression) != nil {
                    result.append(.code(firstLine, lines.dropFirst().joined(separator: "\n")))
                } else {
                    result.append(.code("code", part))
                }
            }
        }

        return result.isEmpty ? [.text(content)] : result
    }
}

private enum HermesRenderedBlock: Equatable {
    case text(String)
    case code(String, String)
}

private struct HermesCodeBlock: View {
    let language: String
    let code: String
    let theme: IOSThemeTokens

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(language)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.textSecondary)
                .accessibilityLabel("Copy \(language) code")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(theme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(theme.backgroundSecondary.opacity(0.65), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.borderSubtle, lineWidth: 1)
        )
    }
}
