import SwiftUI
import UIKit
import Translation

// MARK: - Translation

@available(iOS 18.0, *)
struct IOSTranslationView: View {
    @Environment(\.themeTokens) private var theme
    @Environment(\.iosToolEntryContext) private var toolEntryContext
    @State private var inputText = ""
    @State private var translatedText = ""
    @State private var sourceLanguage: AppLanguage = .zhHans
    @State private var targetLanguage: AppLanguage = .en
    @State private var isTranslating = false
    @State private var copyFeedback = false
    @State private var errorMessage: String?
    @State private var translationConfig: TranslationSession.Configuration?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                languageBar
                inputSection
                translateButton
                resultSection
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.clear)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("ios_tools_translate")
        .iosToolTitleDisplayMode(toolEntryContext)
        .toolbar(toolEntryContext.tabBarVisibility, for: .tabBar)
        .iosToolNavigationChrome(theme, showsBackButton: toolEntryContext.showsBackButton)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("ios_tools_translate_clear_input") {
                        isInputFocused = false
                        inputText = ""
                    }
                    Button("ios_tools_translate_clear_result") {
                        isInputFocused = false
                        translatedText = ""
                        errorMessage = nil
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .iosToolToolbarIcon(theme)
                }
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("ios_common_done") {
                    isInputFocused = false
                }
            }
        }
        .translationTask(translationConfig) { session in
            await performTranslation(session: session)
        }
    }

    // MARK: - Language Bar

    private var languageBar: some View {
        HStack(spacing: 12) {
            languagePicker("Source", selection: $sourceLanguage)

            Button {
                isInputFocused = false
                withAnimation(.easeInOut(duration: 0.25)) {
                    let temp = sourceLanguage
                    sourceLanguage = targetLanguage
                    targetLanguage = temp
                }
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.brandPrimary)
                    .frame(width: 36, height: 36)
                    .iosGlassContainer(theme, cornerRadius: 10)
            }

            languagePicker("Target", selection: $targetLanguage)
        }
    }

    private func languagePicker(_ label: String, selection: Binding<AppLanguage>) -> some View {
        Menu {
            ForEach(AppLanguage.allCases) { lang in
                Button {
                    isInputFocused = false
                    selection.wrappedValue = lang
                } label: {
                    HStack {
                        Text(lang.displayName)
                        if selection.wrappedValue == lang {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selection.wrappedValue.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .iosGlassContainer(theme, cornerRadius: 12)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(theme.borderSubtle, lineWidth: 1)
            )
        }
    }

    // MARK: - Input

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ios_tools_translate_input")
                .font(.headline)
                .foregroundStyle(theme.textPrimary)

            ZStack(alignment: .topLeading) {
                if inputText.isEmpty {
                    Text("ios_tools_translate_input_placeholder")
                        .foregroundStyle(theme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }

                TextEditor(text: $inputText)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .focused($isInputFocused)
                    .frame(minHeight: 140)
                    .padding(10)
            }
            .iosGlassContainer(theme, cornerRadius: 18)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(theme.borderSubtle, lineWidth: 1)
            )
        }
    }

    // MARK: - Translate Button

    private var translateButton: some View {
        Button {
            startTranslation()
        } label: {
            if isTranslating {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Text("ios_tools_translate_button")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(theme.brandPrimary)
        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTranslating)
    }

    // MARK: - Result

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ios_tools_translate_result")
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(theme.warning)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if translatedText.isEmpty {
                Text("ios_tools_translate_result_placeholder")
                    .foregroundStyle(theme.textSecondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .iosGlassContainer(theme, cornerRadius: 18)
            } else {
                ScrollView {
                    Text(translatedText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                .frame(minHeight: 100, alignment: .top)
                .iosGlassContainer(theme, cornerRadius: 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(theme.borderSubtle, lineWidth: 1)
                )

                IOSToolCopyButton(isCopied: copyFeedback) {
                    copyTranslation()
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isInputFocused = false
        }
        .animation(.easeOut(duration: 0.25), value: copyFeedback)
    }

    // MARK: - Translation Logic

    private func startTranslation() {
        isInputFocused = false
        errorMessage = nil
        isTranslating = true

        if translationConfig == nil {
            translationConfig = .init(
                source: sourceLanguage.localeLanguage,
                target: targetLanguage.localeLanguage
            )
        } else {
            translationConfig?.source = sourceLanguage.localeLanguage
            translationConfig?.target = targetLanguage.localeLanguage
            translationConfig?.invalidate()
        }
    }

    private func performTranslation(session: TranslationSession) async {
        do {
            let response = try await session.translate(inputText)
            translatedText = response.targetText
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "ios_tools_translate_error")
        }
        isTranslating = false
    }

    private func copyTranslation() {
        UIPasteboard.general.string = translatedText
        copyFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            copyFeedback = false
        }
    }
}

@available(iOS 18.0, *)
enum AppLanguage: String, CaseIterable, Identifiable {
    case zhHans = "zh-Hans"
    case en = "en"
    case ja = "ja"
    case ko = "ko"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .zhHans: return "中文"
        case .en: return "English"
        case .ja: return "日本語"
        case .ko: return "한국어"
        }
    }

    var localeLanguage: Locale.Language {
        Locale.Language(identifier: rawValue)
    }
}
