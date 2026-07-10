import DevBarCore
import Foundation
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit
import WebKit

struct IOSHermesChatView: View {
    @EnvironmentObject private var appViewModel: IOSAppViewModel
    @Environment(\.themeTokens) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isComposerFocused: Bool
    @State private var isAttachmentPanelPresented = false
    @State private var isCameraPresented = false
    @State private var isFileImporterPresented = false
    @State private var isVoiceInputMode = false
    @State private var isPressingVoiceInput = false
    @State private var isVoiceInputCancelled = false
    @State private var draftBeforeVoiceInput = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var pendingImageAttachments: [IOSHermesImageAttachment] = []
    @State private var hasRegisteredChatInteraction = false
    @State private var hasPerformedInitialScroll = false
    @StateObject private var speechManager = IOSSpeechManager()
    @StateObject private var viewModel: IOSHermesChatViewModel

    private let provider: ChatBotProviderKind
    private let initialConversation: IOSHermesConversation?
    private let initialMessages: [IOSHermesChatViewModel.Message]?
    private let initialDraft: String
    private let onBack: (() -> Void)?
    private let viewCreatedAt: CFAbsoluteTime

    init(
        provider: ChatBotProviderKind = .hermes,
        conversation: IOSHermesConversation? = nil,
        initialMessages: [IOSHermesChatViewModel.Message]? = nil,
        initialSettings: HermesSettings? = nil,
        initialAPIKey: String? = nil,
        initialDraft: String = "",
        onBack: (() -> Void)? = nil
    ) {
        self.provider = conversation?.chatProvider ?? provider
        self.initialConversation = conversation
        self.initialMessages = initialMessages
        self.initialDraft = initialDraft
        self.onBack = onBack
        self.viewCreatedAt = CFAbsoluteTimeGetCurrent()
        _viewModel = StateObject(
            wrappedValue: IOSHermesChatViewModel(
                conversation: conversation,
                prefetchedMessages: initialMessages,
                settings: initialSettings,
                apiKey: initialAPIKey,
                provider: conversation?.chatProvider ?? provider
            )
        )
        IOSDebugLogger.log(
            "HermesChat",
            "view init conversation=\(conversation?.id.uuidString ?? "-") prefetched=\(initialMessages?.count ?? -1)"
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if case .failed(let message) = viewModel.status {
                errorBanner(message)
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 18) {
                        if !viewModel.isConfigured {
                            missingConfigCard
                        } else if viewModel.messages.isEmpty {
                            emptyState
                        }

                        ForEach(viewModel.messages) { message in
                            HermesChatRow(message: message, theme: theme)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 22)
                    .padding(.bottom, chatScrollBottomPadding)
                }
                .scrollDismissesKeyboard(.interactively)
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissChatInput()
                }
                .onAppear {
                    performInitialScrollToBottom(proxy)
                }
                .onChange(of: viewModel.messages) { _, messages in
                    guard let lastID = messages.last?.id else { return }
                    // Messages loaded after the view appeared (async fetch). Keep the
                    // initial-scroll flag in sync so the jump-to-bottom still happens.
                    if !hasPerformedInitialScroll {
                        hasPerformedInitialScroll = true
                        proxy.scrollTo(lastID, anchor: .bottom)
                        return
                    }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
                .onChange(of: isComposerFocused) { _, focused in
                    if focused {
                        isVoiceInputMode = false
                        isAttachmentPanelPresented = false
                        scrollToLatestMessage(proxy)
                    }
                }
                .onChange(of: isAttachmentPanelPresented) { _, presented in
                    if presented {
                        scrollToLatestMessage(proxy)
                    }
                }
            }
        }
        .background {
            chatBackground
                .ignoresSafeArea()
        }
        .safeAreaInset(edge: .bottom) {
            bottomInputArea
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            IOSHermesCameraPicker { name, data in
                let photoLabel = String(localized: "ios_hermes_attachment_photo_label")
                if let data,
                   let attachment = Self.imageAttachment(from: data, displayName: name) {
                    pendingImageAttachments.append(attachment)
                    appendAttachmentReference(name: attachment.displayName, type: photoLabel)
                } else {
                    appendAttachmentReference(name: name, type: photoLabel)
                }
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                appendAttachmentReference(name: url.lastPathComponent, type: String(localized: "ios_hermes_attachment_file_label"))
            }
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task {
                await appendPhotoAttachment(from: item)
                selectedPhotoItem = nil
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .background {
            IOSNavigationPopGestureEnabler()
                .frame(width: 0, height: 0)
        }
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                chatBackButton
            }

            ToolbarItem(placement: .principal) {
                navigationTitleView
            }
        }
        .onAppear {
            let start = CFAbsoluteTimeGetCurrent()
            debugLog("view onAppear begin conversation=\(initialConversation?.id.uuidString ?? "-") messages=\(viewModel.messages.count) viewAge=\(elapsedMilliseconds(since: viewCreatedAt))ms")
            registerChatInteractionIfNeeded()
            if viewModel.conversation == nil {
                viewModel.load(conversation: initialConversation, prefetchedMessages: initialMessages)
            }
            if viewModel.messages.isEmpty,
               viewModel.draft.isEmpty,
               !initialDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                viewModel.draft = initialDraft
                isComposerFocused = true
            }
            configureViewModel()
            // Re-attach to a run that was still in flight when this conversation was last open.
            viewModel.resumeActiveRunIfNeeded(modelContext: modelContext)
            debugLog("view onAppear end messages=\(viewModel.messages.count) configured=\(viewModel.isConfigured) dt=\(elapsedMilliseconds(since: start))ms")
            Task { @MainActor in
                await Task.yield()
                debugLog("view post-yield checkpoint messages=\(viewModel.messages.count) dt=\(elapsedMilliseconds(since: start))ms")
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Returning to the foreground: pick up a run that kept executing server-side while
            // the app was backgrounded / off-network.
            if phase == .active {
                viewModel.resumeActiveRunIfNeeded(modelContext: modelContext)
            }
        }
        .onChange(of: appViewModel.hermesSettings) { _, _ in
            configureViewModel()
        }
        .onChange(of: appViewModel.hermesSettingsRevision) { _, _ in
            configureViewModel()
        }
        .onDisappear {
            resetVoiceInput()
            unregisterChatInteractionIfNeeded()
        }
        .accessibilityIdentifier("ios.hermes.chat.screen")
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(theme.textTertiary)
            Text("ios_hermes_empty_title")
                .font(.headline)
                .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 104)
    }

    private var missingConfigCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("ios_hermes_missing_config_title", systemImage: "key")
                .font(.headline.weight(.semibold))
                .foregroundStyle(theme.textPrimary)
            Text(missingConfigText)
                .font(.subheadline)
                .foregroundStyle(theme.textSecondary)
            NavigationLink {
                IOSSettingsView()
            } label: {
                Label("ios_hermes_open_settings", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(theme.surfacePrimary.opacity(theme.isGeek ? 0.74 : 1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(theme.borderSubtle, lineWidth: 1)
        }
    }

    private var missingConfigText: String {
        String(localized: "ios_hermes_missing_config_detail")
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
            Text(message)
                .font(theme.footnoteFont)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .foregroundStyle(theme.danger)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(theme.danger.opacity(0.12), in: Capsule())
        .overlay {
            Capsule()
                .stroke(theme.danger.opacity(0.18), lineWidth: 1)
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Button {
                guard !viewModel.isBusy else { return }
                isComposerFocused = false
                withAnimation(.easeOut(duration: 0.2)) {
                    isAttachmentPanelPresented.toggle()
                }
            } label: {
                Image(systemName: isAttachmentPanelPresented ? "xmark" : "plus")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(composerIconForeground)
                    .frame(width: 42, height: 42)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isBusy == false && viewModel.isConfigured == false)
            .accessibilityLabel(Text(isAttachmentPanelPresented ? "ios_common_close" : "ios_hermes_attach_file"))

            if isVoiceInputMode {
                voiceInputButton
            } else {
                TextField(String(localized: "ios_hermes_input_hint"), text: $viewModel.draft, axis: .vertical)
                    .focused($isComposerFocused)
                    .lineLimit(1...4)
                    .padding(.vertical, 11)
                    .foregroundStyle(theme.textPrimary)
                    .tint(theme.brandPrimary)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityIdentifier("ios.hermes.chat.input")
            }

            Button(action: trailingComposerAction) {
                trailingButtonLabel
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isBusy == false && viewModel.isConfigured == false)
            .accessibilityIdentifier("ios.hermes.chat.send")
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .background(composerContainerBackground, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(theme.borderSubtle.opacity(theme.isGeek ? 0.34 : 0.22), lineWidth: 1)
        }
        .shadow(color: .black.opacity(theme.isGeek ? 0.34 : 0.12), radius: 18, y: 8)
    }

    private var composerModeButton: some View {
        Button {
            toggleVoiceInputMode()
        } label: {
            composerModeButtonIcon
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ios.hermes.chat.voiceMode")
    }

    @ViewBuilder
    private var composerModeButtonIcon: some View {
        if isVoiceInputMode {
            inputModeIcon(systemName: "keyboard", size: 15)
        } else {
            inputModeIcon(systemName: "microphone", size: 15)
        }
    }

    private func inputModeIcon(systemName: String, size: CGFloat) -> some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(composerIconForeground)
            .frame(width: 42, height: 42)
            .contentShape(Circle())
    }

    private var bottomInputArea: some View {
        VStack(spacing: 10) {
            if isAttachmentPanelPresented {
                attachmentPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            composer
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
        .animation(.easeOut(duration: 0.2), value: isAttachmentPanelPresented)
    }

    private var attachmentPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 0) {
                attachmentPhotoButton
                attachmentActionButton(title: "ios_hermes_attach_camera", systemImage: "camera.fill") {
                    isAttachmentPanelPresented = false
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        isCameraPresented = true
                    } else {
                        appendAttachmentReference(
                            name: String(localized: "ios_hermes_attachment_camera_label"),
                            type: String(localized: "ios_hermes_attachment_photo_label")
                        )
                    }
                }
                attachmentActionButton(title: "ios_hermes_attach_voice", systemImage: "mic.fill") {
                    isAttachmentPanelPresented = false
                    isVoiceInputMode = true
                    isComposerFocused = false
                }
                attachmentActionButton(title: "ios_hermes_attach_file", systemImage: "folder.fill") {
                    isAttachmentPanelPresented = false
                    isFileImporterPresented = true
                }
            }
            .frame(maxWidth: .infinity)

            Text("ios_hermes_attachment_message")
                .font(theme.captionFont)
                .foregroundStyle(theme.textTertiary)
                .padding(.horizontal, 8)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .frame(height: 160)
        .background(composerContainerBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(theme.borderSubtle.opacity(theme.isGeek ? 0.32 : 0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(theme.isGeek ? 0.22 : 0.08), radius: 14, y: 6)
    }

    private var attachmentPhotoButton: some View {
        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            attachmentTileContent(title: "ios_hermes_attach_photo", systemImage: "photo.fill")
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func attachmentActionButton(title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            attachmentTileContent(title: title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func attachmentTileContent(title: LocalizedStringKey, systemImage: String) -> some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(attachmentTileBackground)
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(theme.borderSubtle.opacity(theme.isGeek ? 0.34 : 0.18), lineWidth: 1)
                }

            Text(title)
                .font(theme.captionFont)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var trailingButtonLabel: some View {
        Image(systemName: trailingButtonImage)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(trailingButtonForeground)
            .frame(width: 42, height: 42)
            .contentShape(Circle())
    }

    private var trailingButtonImage: String {
        if viewModel.isBusy { return "stop.circle" }
        if viewModel.canSend { return "arrow.up.circle.fill" }
        return isVoiceInputMode ? "keyboard" : "microphone"
    }

    private var trailingButtonForeground: Color {
        if viewModel.canSend {
            return theme.brandPrimary
        }
        return composerIconForeground
    }

    private var composerIconForeground: Color {
        theme.isGeek ? Color.white.opacity(0.92) : theme.textPrimary
    }

    private var chatBackground: some View {
        hermesPageBackground
    }

    private var hermesPageBackground: Color {
        theme.isGeek || colorScheme == .dark ? .black : theme.backgroundSecondary
    }

    private var composerFieldBackground: Color {
        theme.isGeek ? theme.surfacePrimary.opacity(0.82) : theme.surfacePrimary
    }

    private var inputBarBackground: Color {
        theme.isGeek ? theme.backgroundPrimary.opacity(0.96) : theme.backgroundSecondary
    }

    private var composerContainerBackground: Color {
        theme.isGeek ? theme.surfacePrimary.opacity(0.72) : theme.surfacePrimary.opacity(0.96)
    }

    private var attachmentTileBackground: Color {
        theme.isGeek ? theme.surfacePrimary.opacity(0.78) : theme.surfacePrimary
    }

    private var suggestionBackground: Color {
        theme.isGeek ? theme.surfacePrimary.opacity(0.66) : theme.surfacePrimary
    }

    private var chatScrollBottomPadding: CGFloat {
        // The composer (and, when open, the attachment panel) lives in a bottom safeAreaInset,
        // which already reserves its height below the scroll content. Only a small breathing gap
        // is needed here — anything more leaves a large empty band above the input box.
        12
    }

    private var headerTitle: String {
        providerDisplayTitle
    }

    private var providerRemark: String {
        appViewModel.hermesSettings.chatRemark(for: provider)
    }

    private var providerDisplayTitle: String {
        let trimmed = providerRemark.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "ChatBot" : trimmed
    }

    private var currentTag: String {
        let tag = appViewModel.hermesSettings.chatTag(for: provider)
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? provider.title : trimmed
    }

    private var currentEditableTag: String {
        appViewModel.hermesSettings.chatTag(for: provider)
    }

    private var remarkBinding: Binding<String> {
        Binding {
            providerRemark
        } set: { newValue in
            appViewModel.updateChatProviderMetadata(provider: provider, remark: newValue, tag: currentEditableTag)
        }
    }

    private var tagBinding: Binding<String> {
        Binding {
            currentEditableTag
        } set: { newValue in
            appViewModel.updateChatProviderMetadata(provider: provider, remark: providerRemark, tag: newValue)
        }
    }

    private var navigationTitleView: some View {
        VStack(spacing: 1) {
            HStack(alignment: .center, spacing: 7) {
                Image("HermesBot")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 26, height: 26)
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(theme.isGeek ? 0.24 : 0.16), lineWidth: 0.5)
                    }

                Text(headerTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(currentTag)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(chatHeaderTagForeground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(chatHeaderTagBackground, in: Capsule())
            }

            if viewModel.isBusy {
                HermesThinkingStatusView(theme: theme)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: 260, alignment: .center)
    }

    private var chatHeaderTagForeground: Color {
        theme.isGeek ? .black : theme.backgroundPrimary
    }

    private var chatHeaderTagBackground: Color {
        theme.brandPrimary.opacity(theme.isGeek ? 0.92 : 0.78)
    }

    private var chatBackButton: some View {
        Button {
            if let onBack {
                onBack()
            } else {
                dismiss()
            }
        } label: {
            Image(systemName: "chevron.left")
                .iosToolToolbarIcon(theme)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("ios_common_back")
    }

    private var voiceInputButton: some View {
        Text(voiceInputTitle)
            .font(.headline.weight(.semibold))
            .foregroundStyle(voiceInputForeground)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 42)
            .background(voiceButtonBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(voiceButtonBorder, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                IOSHermesPressToTalkTouchSurface(
                    onChanged: { translation in
                        updatePressToTalk(translation: translation)
                    },
                    onEnded: { translation in
                        finishPressToTalk(translation: translation)
                    },
                    onCancelled: {
                        stopPressToTalk(cancelled: true)
                    }
                )
            }
            .accessibilityIdentifier("ios.hermes.chat.voiceInput")
    }

    private var voiceInputTitle: LocalizedStringKey {
        if isVoiceInputCancelled { return "ios_hermes_voice_release_cancel" }
        if isPressingVoiceInput { return "ios_hermes_voice_release" }
        return "ios_hermes_voice_hold"
    }

    private var voiceInputForeground: Color {
        if isVoiceInputCancelled { return theme.danger }
        if isPressingVoiceInput { return theme.brandPrimary }
        return theme.textPrimary
    }

    private var voiceButtonBackground: Color {
        if isVoiceInputCancelled {
            return theme.danger.opacity(theme.isGeek ? 0.16 : 0.12)
        }
        if isPressingVoiceInput {
            return theme.brandPrimary.opacity(theme.isGeek ? 0.16 : 0.12)
        }
        return composerFieldBackground
    }

    private var voiceButtonBorder: Color {
        if isVoiceInputCancelled { return theme.danger.opacity(0.72) }
        return isPressingVoiceInput ? theme.brandPrimary.opacity(0.72) : theme.borderSubtle.opacity(0.7)
    }

    private func configureViewModel() {
        let start = CFAbsoluteTimeGetCurrent()
        viewModel.configure(
            settings: appViewModel.hermesSettings,
            apiKey: appViewModel.hermesAPIKey,
            provider: provider
        )
        debugLog("configure provider=\(provider.rawValue) configured=\(viewModel.isConfigured) dt=\(elapsedMilliseconds(since: start))ms")
    }

    private func registerChatInteractionIfNeeded() {
        guard !hasRegisteredChatInteraction else { return }
        hasRegisteredChatInteraction = true
        if !appViewModel.claimHermesChatInteractionReservation(reason: "chat appear") {
            appViewModel.beginHermesChatInteraction(reason: "chat appear")
        }
    }

    private func unregisterChatInteractionIfNeeded() {
        guard hasRegisteredChatInteraction else { return }
        hasRegisteredChatInteraction = false
        if appViewModel.isHermesToolSelectionActive {
            appViewModel.endHermesChatInteraction()
        } else {
            appViewModel.forceEndHermesChatInteraction(reason: "chat disappear outside hermes tab")
        }
    }

    private func dismissChatInput() {
        isComposerFocused = false
        isAttachmentPanelPresented = false
    }

    private func trailingComposerAction() {
        if viewModel.isBusy {
            viewModel.cancel()
            return
        }

        if viewModel.canSend {
            sendCurrentDraft()
        } else {
            toggleVoiceInputMode()
        }
    }

    private func sendCurrentDraft() {
        guard viewModel.canSend else { return }
        isComposerFocused = false
        isAttachmentPanelPresented = false
        _ = viewModel.sendDraft(
            modelContext: modelContext,
            title: providerDisplayTitle,
            imageAttachments: pendingImageAttachments
        )
        pendingImageAttachments = []
    }

    private func toggleVoiceInputMode() {
        if isVoiceInputMode {
            isVoiceInputMode = false
            isComposerFocused = true
        } else {
            isComposerFocused = false
            isAttachmentPanelPresented = false
            isVoiceInputMode = true
        }
        stopPressToTalk()
    }

    private func updatePressToTalk(translation: CGSize) {
        startPressToTalkIfNeeded()
        let shouldCancel = translation.height < -48
        if shouldCancel != isVoiceInputCancelled {
            isVoiceInputCancelled = shouldCancel
            if shouldCancel {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
        }
    }

    private func startPressToTalkIfNeeded() {
        guard !isPressingVoiceInput, !speechManager.isRecording else { return }
        isPressingVoiceInput = true
        isVoiceInputCancelled = false
        draftBeforeVoiceInput = viewModel.draft
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        speechManager.clear()
        speechManager.startRecording()
    }

    private func finishPressToTalk(translation: CGSize) {
        let shouldCancel = isVoiceInputCancelled || translation.height < -48
        stopPressToTalk(cancelled: shouldCancel)
    }

    private func stopPressToTalk(cancelled: Bool = false) {
        guard isPressingVoiceInput || speechManager.isRecording else { return }
        let recognizedSpeech = speechTextSnapshot()
        isPressingVoiceInput = false
        isVoiceInputCancelled = false
        speechManager.stopRecording(commit: false)
        if cancelled {
            speechManager.clear()
        } else {
            speechManager.clear()
            commitRecognizedSpeech(recognizedSpeech, baseDraft: draftBeforeVoiceInput)
        }
        draftBeforeVoiceInput = ""
    }

    private func resetVoiceInput() {
        if speechManager.isRecording {
            speechManager.stopRecording()
        }
        isPressingVoiceInput = false
        isVoiceInputCancelled = false
    }

    private func speechTextSnapshot() -> String {
        [speechManager.recognizedText, speechManager.partialText]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func commitRecognizedSpeech(_ text: String, baseDraft: String) {
        let trimmed = collapsedRecognizedSpeech(text)
        guard !trimmed.isEmpty else { return }

        let base = baseDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty {
            viewModel.draft = trimmed
        } else if trimmed.hasPrefix(base) {
            viewModel.draft = trimmed
        } else if !base.hasSuffix(trimmed) {
            viewModel.draft = base + " " + trimmed
        }
        isVoiceInputMode = false
        isAttachmentPanelPresented = false
        DispatchQueue.main.async {
            isComposerFocused = true
        }
    }

    private func collapsedRecognizedSpeech(_ text: String) -> String {
        let parts = text
            .replacingOccurrences(of: "\n", with: " ")
            .split { $0.isWhitespace }
            .map(String.init)

        let collapsed = parts.reduce(into: [String]()) { result, part in
            guard let last = result.last else {
                result.append(part)
                return
            }

            if part == last || last.hasPrefix(part) {
                return
            }

            if part.hasPrefix(last) {
                result[result.count - 1] = part
            } else {
                result.append(part)
            }
        }

        return collapsed.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func appendAttachmentReference(name: String, type: String) {
        let reference = String(format: String(localized: "ios_hermes_attachment_reference"), type, name)
        if viewModel.draft.isEmpty {
            viewModel.draft = reference
        } else {
            viewModel.draft += "\n" + reference
        }
        isComposerFocused = true
    }

    private func appendPhotoAttachment(from item: PhotosPickerItem) async {
        isAttachmentPanelPresented = false
        let photoLabel = String(localized: "ios_hermes_attachment_photo_label")
        guard let data = try? await item.loadTransferable(type: Data.self),
              let attachment = Self.imageAttachment(from: data, displayName: photoLabel) else {
            appendAttachmentReference(name: photoLabel, type: photoLabel)
            return
        }

        pendingImageAttachments.append(attachment)
        appendAttachmentReference(name: attachment.displayName, type: photoLabel)
    }

    private static func imageAttachment(from data: Data, displayName: String) -> IOSHermesImageAttachment? {
        guard let image = UIImage(data: data),
              let jpegData = image.hermesJPEGData(maxDimension: 1_600, quality: 0.86) else {
            return nil
        }

        return IOSHermesImageAttachment(
            displayName: displayName,
            dataURL: "data:image/jpeg;base64,\(jpegData.base64EncodedString())"
        )
    }

    private func performInitialScrollToBottom(_ proxy: ScrollViewProxy) {
        guard !hasPerformedInitialScroll else { return }
        guard let lastID = viewModel.messages.last?.id else { return }
        hasPerformedInitialScroll = true
        // Prefetched conversations arrive fully populated, so viewModel.messages
        // never "changes" and the onChange scroll never fires — the list would sit
        // pinned to the first message. Jump straight to the newest one, re-anchoring
        // a few times because Markdown rows in the LazyVStack measure asynchronously.
        proxy.scrollTo(lastID, anchor: .bottom)
        for delay in [0.05, 0.2, 0.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }

    private func scrollToLatestMessage(_ proxy: ScrollViewProxy) {
        guard let lastID = viewModel.messages.last?.id else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }

    private func debugLog(_ message: String) {
        IOSDebugLogger.log("HermesChat", message)
    }

    private func elapsedMilliseconds(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1_000)
    }
}

private struct HermesChatRow: View {
    let message: IOSHermesChatViewModel.Message
    let theme: IOSThemeTokens
    @State private var isHTMLPreviewPresented = false
    @State private var hasLoggedAppear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if message.role == .user {
                HStack(alignment: .top) {
                    Spacer(minLength: 72)
                    HermesUserMessageContent(content: message.content, theme: theme)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(userBubbleBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .contextMenu {
                            Button("ios_common_copy") {
                                UIPasteboard.general.string = HermesMessageAttachmentParser.visibleText(from: message.content)
                            }
                        }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if message.content.isEmpty, !message.isComplete {
                        // Streaming bubble awaiting its first token (fresh run or re-attach).
                        HermesThinkingStatusView(theme: theme)
                    } else if isHTMLPreviewPresented, let htmlContent {
                        HermesHTMLPreview(html: htmlContent, theme: theme)
                    } else {
                        HermesMarkdownMessage(
                            content: message.content,
                            theme: theme,
                            htmlRenderControl: htmlContent == nil ? nil : .init(
                                title: isHTMLPreviewPresented ? "ios_hermes_html_show_source" : "ios_hermes_html_render",
                                systemImage: isHTMLPreviewPresented ? "text.alignleft" : "safari",
                                action: toggleHTMLPreview
                            )
                        )
                    }

                    HStack(spacing: 18) {
                        assistantActionButton(title: "ios_common_copy", systemImage: "square.on.square") {
                            UIPasteboard.general.string = message.content
                        }
                        if htmlContent != nil {
                            assistantActionButton(
                                title: isHTMLPreviewPresented ? "ios_hermes_html_show_source" : "ios_hermes_html_render",
                                systemImage: isHTMLPreviewPresented ? "text.alignleft" : "safari"
                            ) {
                                toggleHTMLPreview()
                            }
                        }
                    }
                    .opacity(message.content.isEmpty ? 0 : 1)
                }
                .frame(maxWidth: assistantBubbleMaxWidth, alignment: .leading)
                .contextMenu {
                    Button("ios_common_copy") {
                        UIPasteboard.general.string = message.content
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .onAppear {
            guard !hasLoggedAppear else { return }
            hasLoggedAppear = true
            IOSDebugLogger.log(
                "HermesChat",
                "row appear id=\(message.id.uuidString) role=\(message.role.rawValue) chars=\(message.content.count) html=\(htmlContent != nil) code=\(containsCodeBlock)"
            )
        }
    }

    private func assistantActionButton(
        title: LocalizedStringKey,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.textTertiary)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
    }

    private var containsCodeBlock: Bool {
        message.content.contains("```")
    }

    private var assistantBubbleMaxWidth: CGFloat {
        max(220, min(UIScreen.main.bounds.width - 56, 620))
    }

    private func toggleHTMLPreview() {
        withAnimation(.easeOut(duration: 0.18)) {
            isHTMLPreviewPresented.toggle()
        }
    }

    private var userTextColor: Color {
        theme.isGeek ? Color.white.opacity(0.96) : theme.textPrimary
    }

    private var userBubbleBackground: Color {
        theme.isGeek ? theme.surfaceSecondary.opacity(0.86) : theme.surfaceSecondary.opacity(0.94)
    }

    private var htmlContent: String? {
        HermesHTMLExtractor.extract(from: message.content)
    }
}

private struct HermesThinkingStatusView: View {
    let theme: IOSThemeTokens

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.36)) { context in
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("ios_hermes_replying")

                ForEach(0..<3, id: \.self) { index in
                    Text(".")
                        .opacity(dotOpacity(index: index, date: context.date))
                }
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(theme.textTertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func dotOpacity(index: Int, date: Date) -> Double {
        let phase = Int(date.timeIntervalSinceReferenceDate / 0.36) % 4
        return phase > index ? 1 : 0.28
    }
}

private struct HermesUserMessageContent: View {
    let content: String
    let theme: IOSThemeTokens
    @State private var selectedImageAttachment: HermesMessageAttachmentParser.ImageAttachment?

    private var parsedContent: HermesMessageAttachmentParser.ParsedContent {
        HermesMessageAttachmentParser.parse(content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !parsedContent.text.isEmpty {
                Text(parsedContent.text)
                    .font(theme.bodyFont)
                    .foregroundStyle(textColor)
                    .textSelection(.enabled)
            }

            ForEach(parsedContent.images) { attachment in
                Button {
                    selectedImageAttachment = attachment
                } label: {
                    HermesImageAttachmentPreview(attachment: attachment, theme: theme)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(attachment.displayName))
            }

            ForEach(parsedContent.files) { attachment in
                HermesFileAttachmentPreview(attachment: attachment, theme: theme)
            }
        }
        .fullScreenCover(item: $selectedImageAttachment) { attachment in
            HermesImageAttachmentFullScreenPreview(attachment: attachment, theme: theme)
        }
    }

    private var textColor: Color {
        theme.isGeek ? Color.white.opacity(0.96) : theme.textPrimary
    }
}

private struct HermesImageAttachmentPreview: View {
    let attachment: HermesMessageAttachmentParser.ImageAttachment
    let theme: IOSThemeTokens

    var body: some View {
        if let image = UIImage.hermesImage(fromDataURL: attachment.dataURL) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 210, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    Text(attachment.displayName)
                        .font(theme.captionFont.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.42), in: Capsule())
                        .padding(8)
                }
        } else {
            HermesFileAttachmentPreview(
                attachment: .init(name: attachment.displayName, kind: .image),
                theme: theme
            )
        }
    }
}

private struct HermesImageAttachmentFullScreenPreview: View {
    let attachment: HermesMessageAttachmentParser.ImageAttachment
    let theme: IOSThemeTokens
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = UIImage.hermesImage(fromDataURL: attachment.dataURL) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 12)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo")
                        .font(.system(size: 42, weight: .semibold))
                    Text(attachment.displayName)
                        .font(theme.bodyFont.weight(.semibold))
                        .lineLimit(2)
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(24)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.16), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
            .padding(.trailing, 18)
        }
        .overlay(alignment: .bottomLeading) {
            Text(attachment.displayName)
                .font(theme.footnoteFont.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.black.opacity(0.38), in: Capsule())
                .padding(.leading, 18)
                .padding(.bottom, 18)
        }
    }
}

private struct HermesFileAttachmentPreview: View {
    let attachment: HermesMessageAttachmentParser.FileAttachment
    let theme: IOSThemeTokens

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: attachment.kind.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.brandPrimary)
                .frame(width: 34, height: 34)
                .background(theme.brandPrimary.opacity(theme.isGeek ? 0.18 : 0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(attachment.name)
                .font(theme.footnoteFont.weight(.semibold))
                .foregroundStyle(theme.isGeek ? Color.white.opacity(0.94) : theme.textPrimary)
                .lineLimit(2)
        }
        .frame(maxWidth: 240, alignment: .leading)
        .padding(10)
        .background(theme.surfacePrimary.opacity(theme.isGeek ? 0.38 : 0.62), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private enum HermesMessageAttachmentParser {
    struct ParsedContent {
        var text: String
        var images: [ImageAttachment]
        var files: [FileAttachment]
    }

    struct ImageAttachment: Identifiable {
        let id = UUID()
        var displayName: String
        var dataURL: String
    }

    struct FileAttachment: Identifiable {
        let id = UUID()
        var name: String
        var kind: AttachmentKind
    }

    enum AttachmentKind {
        case file
        case image

        var systemImage: String {
            switch self {
            case .file:
                return "doc.fill"
            case .image:
                return "photo.fill"
            }
        }
    }

    static func parse(_ content: String) -> ParsedContent {
        let persistedImages = IOSHermesImageAttachment.persistedAttachments(in: content)
        let imageNames = Set(persistedImages.map { $0.displayName })
        var textLines: [String] = []
        var files: [FileAttachment] = []

        for line in content.components(separatedBy: .newlines) {
            if IOSHermesImageAttachment.persistedAttachments(in: line).first != nil {
                continue
            }

            if let reference = attachmentReference(from: line) {
                if imageNames.contains(reference.name) {
                    continue
                }
                files.append(
                    FileAttachment(
                        name: reference.name,
                        kind: reference.isImage ? .image : .file
                    )
                )
                continue
            }

            textLines.append(line)
        }

        return ParsedContent(
            text: textLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            images: persistedImages.map { ImageAttachment(displayName: $0.displayName, dataURL: $0.dataURL) },
            files: files
        )
    }

    static func visibleText(from content: String) -> String {
        parse(content).text
    }

    private static func attachmentReference(from line: String) -> (name: String, isImage: Bool)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { return nil }
        let body = String(trimmed.dropFirst().dropLast())
        guard body.hasPrefix("Attachment: ") || body.hasPrefix("附件：") else { return nil }
        let payload = body
            .replacingOccurrences(of: "Attachment: ", with: "")
            .replacingOccurrences(of: "附件：", with: "")
        let parts = payload.components(separatedBy: " - ")
        guard parts.count >= 2 else { return nil }
        let type = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let name = parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let imageTokens = ["photo", "image", "camera", "图片", "照片", "拍照"]
        let isImage = imageTokens.contains { type.localizedCaseInsensitiveContains($0) || name.localizedCaseInsensitiveContains($0) }
        return (name, isImage)
    }
}

private struct AssistantBubbleWidthModifier: ViewModifier {
    let maxWidth: CGFloat
    let usesIntrinsicWidth: Bool

    func body(content: Content) -> some View {
        if usesIntrinsicWidth {
            ViewThatFits(in: .horizontal) {
                content
                    .fixedSize(horizontal: true, vertical: false)
                content
                    .frame(width: maxWidth, alignment: .leading)
            }
        } else {
            content
                .frame(maxWidth: maxWidth, alignment: .leading)
        }
    }
}

struct IOSHermesChatSettingsView: View {
    @EnvironmentObject private var appViewModel: IOSAppViewModel
    let provider: ChatBotProviderKind
    @Binding var remark: String
    @Binding var tag: String
    let theme: IOSThemeTokens

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(theme.brandPrimary.opacity(theme.isGeek ? 0.18 : 0.12))
                            .frame(width: 68, height: 68)
                        Image("HermesBot")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 54, height: 54)
                            .clipShape(Circle())
                            .overlay {
                                Circle()
                                    .stroke(Color.white.opacity(theme.isGeek ? 0.26 : 0.16), lineWidth: 0.8)
                            }
                    }

                    Text(displayName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)

                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)

                VStack(alignment: .leading, spacing: 8) {
                    Text("ios_hermes_chat_remark")
                        .font(theme.captionFont.weight(.semibold))
                        .foregroundStyle(theme.textTertiary)
                        .padding(.horizontal, 16)

                    HStack(spacing: 12) {
                        Text("ios_hermes_chat_remark")
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.textPrimary)
                        TextField(String(localized: "ios_hermes_chat_remark_placeholder"), text: $remark)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.sentences)
                            .foregroundStyle(theme.textPrimary)
                            .tint(theme.brandPrimary)
                    }
                    .frame(minHeight: 52)
                    .padding(.horizontal, 16)
                    .background(settingsRowBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(theme.borderSubtle.opacity(theme.isGeek ? 0.42 : 0.18), lineWidth: 1)
                    }

                    HStack(spacing: 12) {
                        Text("ios_hermes_chat_tag")
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.textPrimary)
                        TextField(String(localized: "ios_hermes_chat_tag_placeholder"), text: $tag)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.words)
                            .foregroundStyle(theme.textPrimary)
                            .tint(theme.brandPrimary)
                    }
                    .frame(minHeight: 52)
                    .padding(.horizontal, 16)
                    .background(settingsRowBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(theme.borderSubtle.opacity(theme.isGeek ? 0.42 : 0.18), lineWidth: 1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
        .background(settingsBackground.ignoresSafeArea())
        .navigationTitle("ios_hermes_chat_settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(settingsNavigationBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(theme.isGeek ? .dark : .light, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
    }

    private var settingsBackground: some View {
        LinearGradient(
            colors: theme.isGeek
                ? [theme.backgroundPrimary, theme.backgroundSecondary.opacity(0.96)]
                : [theme.backgroundSecondary, theme.backgroundPrimary],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var settingsNavigationBackground: Color {
        theme.isGeek ? theme.backgroundPrimary.opacity(0.98) : theme.backgroundSecondary
    }

    private var settingsRowBackground: Color {
        theme.isGeek ? theme.surfacePrimary.opacity(0.66) : theme.surfacePrimary
    }

    private var displayName: String {
        let trimmed = remark.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "ios_hermes_title") : trimmed
    }
}

private struct IOSHermesCameraPicker: UIViewControllerRepresentable {
    let onPicked: (String, Data?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: IOSHermesCameraPicker

        init(parent: IOSHermesCameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let imageData = (info[.originalImage] as? UIImage)?
                .hermesJPEGData(maxDimension: 1_600, quality: 0.86)
            parent.onPicked(String(localized: "ios_hermes_attachment_camera_label"), imageData)
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

private extension UIImage {
    static func hermesImage(fromDataURL dataURL: String) -> UIImage? {
        guard let commaIndex = dataURL.firstIndex(of: ",") else { return nil }
        let base64 = String(dataURL[dataURL.index(after: commaIndex)...])
        guard let data = Data(base64Encoded: base64) else { return nil }
        return UIImage(data: data)
    }

    func hermesJPEGData(maxDimension: CGFloat, quality: CGFloat) -> Data? {
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension else {
            return jpegData(compressionQuality: quality)
        }

        let scale = maxDimension / longestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let scaledImage = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return scaledImage.jpegData(compressionQuality: quality)
    }
}

private enum HermesBubbleTailDirection {
    case left
    case right
}

private struct HermesBubbleShape: Shape {
    let direction: HermesBubbleTailDirection

    func path(in rect: CGRect) -> Path {
        let tailWidth: CGFloat = 8
        let tailHeight: CGFloat = 11
        let cornerRadius: CGFloat = 10
        let bubbleRect: CGRect

        switch direction {
        case .left:
            bubbleRect = CGRect(
                x: rect.minX + tailWidth,
                y: rect.minY,
                width: max(0, rect.width - tailWidth),
                height: rect.height
            )
        case .right:
            bubbleRect = CGRect(
                x: rect.minX,
                y: rect.minY,
                width: max(0, rect.width - tailWidth),
                height: rect.height
            )
        }

        let minX = bubbleRect.minX
        let maxX = bubbleRect.maxX
        let minY = bubbleRect.minY
        let maxY = bubbleRect.maxY
        let tailY = minY + min(22, max(15, rect.height * 0.24))
        var path = Path()

        switch direction {
        case .right:
            path.move(to: CGPoint(x: minX + cornerRadius, y: minY))
            path.addLine(to: CGPoint(x: maxX - cornerRadius, y: minY))
            path.addQuadCurve(to: CGPoint(x: maxX, y: minY + cornerRadius), control: CGPoint(x: maxX, y: minY))
            path.addLine(to: CGPoint(x: maxX, y: tailY - tailHeight * 0.5))
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: tailY),
                control1: CGPoint(x: maxX + tailWidth * 0.28, y: tailY - tailHeight * 0.38),
                control2: CGPoint(x: maxX + tailWidth * 0.76, y: tailY - tailHeight * 0.28)
            )
            path.addCurve(
                to: CGPoint(x: maxX, y: tailY + tailHeight * 0.5),
                control1: CGPoint(x: maxX + tailWidth * 0.76, y: tailY + tailHeight * 0.28),
                control2: CGPoint(x: maxX + tailWidth * 0.28, y: tailY + tailHeight * 0.38)
            )
            path.addLine(to: CGPoint(x: maxX, y: maxY - cornerRadius))
            path.addQuadCurve(to: CGPoint(x: maxX - cornerRadius, y: maxY), control: CGPoint(x: maxX, y: maxY))
            path.addLine(to: CGPoint(x: minX + cornerRadius, y: maxY))
            path.addQuadCurve(to: CGPoint(x: minX, y: maxY - cornerRadius), control: CGPoint(x: minX, y: maxY))
            path.addLine(to: CGPoint(x: minX, y: minY + cornerRadius))
            path.addQuadCurve(to: CGPoint(x: minX + cornerRadius, y: minY), control: CGPoint(x: minX, y: minY))
            path.closeSubpath()
        case .left:
            path.move(to: CGPoint(x: maxX - cornerRadius, y: minY))
            path.addLine(to: CGPoint(x: minX + cornerRadius, y: minY))
            path.addQuadCurve(to: CGPoint(x: minX, y: minY + cornerRadius), control: CGPoint(x: minX, y: minY))
            path.addLine(to: CGPoint(x: minX, y: tailY - tailHeight * 0.5))
            path.addCurve(
                to: CGPoint(x: rect.minX, y: tailY),
                control1: CGPoint(x: minX - tailWidth * 0.28, y: tailY - tailHeight * 0.38),
                control2: CGPoint(x: minX - tailWidth * 0.76, y: tailY - tailHeight * 0.28)
            )
            path.addCurve(
                to: CGPoint(x: minX, y: tailY + tailHeight * 0.5),
                control1: CGPoint(x: minX - tailWidth * 0.76, y: tailY + tailHeight * 0.28),
                control2: CGPoint(x: minX - tailWidth * 0.28, y: tailY + tailHeight * 0.38)
            )
            path.addLine(to: CGPoint(x: minX, y: maxY - cornerRadius))
            path.addQuadCurve(to: CGPoint(x: minX + cornerRadius, y: maxY), control: CGPoint(x: minX, y: maxY))
            path.addLine(to: CGPoint(x: maxX - cornerRadius, y: maxY))
            path.addQuadCurve(to: CGPoint(x: maxX, y: maxY - cornerRadius), control: CGPoint(x: maxX, y: maxY))
            path.addLine(to: CGPoint(x: maxX, y: minY + cornerRadius))
            path.addQuadCurve(to: CGPoint(x: maxX - cornerRadius, y: minY), control: CGPoint(x: maxX, y: minY))
            path.closeSubpath()
        }

        return path
    }
}

private struct HermesMarkdownMessage: View {
    let content: String
    let theme: IOSThemeTokens
    let htmlRenderControl: HermesCodeBlockAction?

    init(content: String, theme: IOSThemeTokens, htmlRenderControl: HermesCodeBlockAction? = nil) {
        self.content = content
        self.theme = theme
        self.htmlRenderControl = htmlRenderControl
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let text):
                    Text(inlineMarkdown(text))
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.textPrimary)
                        .textSelection(.enabled)
                case .heading(let level, let text):
                    Text(inlineMarkdown(text))
                        .font(headingFont(for: level))
                        .foregroundStyle(theme.textPrimary)
                        .textSelection(.enabled)
                case .listItem(let text):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\u{2022}")
                            .font(theme.bodyFont.weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                        Text(inlineMarkdown(text))
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.textPrimary)
                            .textSelection(.enabled)
                    }
                case .quote(let text):
                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(theme.brandPrimary.opacity(0.46))
                            .frame(width: 3)
                        Text(inlineMarkdown(text))
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.textSecondary)
                            .textSelection(.enabled)
                    }
                case .code(let language, let code):
                    HermesCodeBlock(
                        language: language,
                        code: code,
                        theme: theme,
                        htmlRenderControl: htmlControl(for: language, code: code)
                    )
                case .table(let headers, let rows):
                    HermesTableView(headers: headers, rows: rows, theme: theme)
                }
            }
        }
    }

    private var blocks: [HermesMarkdownBlock] {
        HermesMarkdownParser.parse(content)
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1:
            return .title2.weight(.bold)
        case 2:
            return .title3.weight(.bold)
        default:
            return .headline.weight(.semibold)
        }
    }

    private func htmlControl(for language: String, code: String) -> HermesCodeBlockAction? {
        guard let htmlRenderControl else { return nil }
        let normalizedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedLanguage.contains("html") || normalizedCode.hasPrefix("<!doctype html") || normalizedCode.hasPrefix("<html") {
            return htmlRenderControl
        }
        return nil
    }
}

private struct HermesCodeBlockAction {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void
}

private enum HermesMarkdownBlock: Equatable {
    case paragraph(String)
    case heading(Int, String)
    case listItem(String)
    case quote(String)
    case code(String, String)
    case table([String], [[String]])
}

private enum HermesMarkdownParser {
    static func parse(_ source: String) -> [HermesMarkdownBlock] {
        let lines = source.components(separatedBy: .newlines)
        var blocks: [HermesMarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                var codeLines: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                blocks.append(.code(language.isEmpty ? "code" : language, codeLines.joined(separator: "\n")))
                index += 1
                continue
            }

            if let level = headingLevel(trimmed) {
                let text = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level, text))
                index += 1
                continue
            }

            if isTableStart(lines, index: index) {
                let headers = tableCells(from: lines[index])
                index += 2
                var rows: [[String]] = []
                while index < lines.count, lines[index].contains("|"), !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(tableCells(from: lines[index]))
                    index += 1
                }
                blocks.append(.table(headers, rows))
                continue
            }

            if trimmed.hasPrefix(">") {
                blocks.append(.quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
                index += 1
                continue
            }

            if let listText = listItemText(trimmed) {
                blocks.append(.listItem(listText))
                index += 1
                continue
            }

            var paragraph = [trimmed]
            index += 1
            while index < lines.count {
                let next = lines[index].trimmingCharacters(in: .whitespaces)
                if next.isEmpty || next.hasPrefix("```") || next.hasPrefix(">") || headingLevel(next) != nil || listItemText(next) != nil || isTableStart(lines, index: index) {
                    break
                }
                paragraph.append(next)
                index += 1
            }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
        }

        return blocks.isEmpty ? [.paragraph(source)] : blocks
    }

    private static func headingLevel(_ line: String) -> Int? {
        let count = line.prefix(while: { $0 == "#" }).count
        guard (1...3).contains(count), line.dropFirst(count).first == " " else { return nil }
        return count
    }

    private static func listItemText(_ line: String) -> String? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        guard let dotIndex = line.firstIndex(of: ".") else { return nil }
        let prefix = line[..<dotIndex]
        guard !prefix.isEmpty, prefix.allSatisfy(\.isNumber) else { return nil }
        let afterDot = line[line.index(after: dotIndex)...]
        guard afterDot.first == " " else { return nil }
        return String(afterDot.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private static func isTableStart(_ lines: [String], index: Int) -> Bool {
        guard index + 1 < lines.count else { return false }
        guard lines[index].contains("|") else { return false }
        let divider = lines[index + 1].trimmingCharacters(in: .whitespaces)
        guard divider.contains("|"), divider.contains("-") else { return false }
        let allowed = CharacterSet(charactersIn: "|-: ")
        return divider.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func tableCells(from line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }
        return value.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

private struct HermesCodeBlock: View {
    let language: String
    let code: String
    let theme: IOSThemeTokens
    let htmlRenderControl: HermesCodeBlockAction?

    init(
        language: String,
        code: String,
        theme: IOSThemeTokens,
        htmlRenderControl: HermesCodeBlockAction? = nil
    ) {
        self.language = language
        self.code = code
        self.theme = theme
        self.htmlRenderControl = htmlRenderControl
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(language)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                HStack(spacing: 10) {
                    codeActionButton(title: "ios_common_copy", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = code
                    }
                    if let htmlRenderControl {
                        codeActionButton(
                            title: htmlRenderControl.title,
                            systemImage: htmlRenderControl.systemImage,
                            action: htmlRenderControl.action
                        )
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(theme.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(codeBlockBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(theme.borderSubtle.opacity(theme.isGeek ? 0.38 : 0.18), lineWidth: 1)
        }
    }

    private var codeBlockBackground: Color {
        theme.isGeek ? theme.surfacePrimary.opacity(0.74) : theme.surfacePrimary.opacity(0.96)
    }

    private func codeActionButton(
        title: LocalizedStringKey,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.textPrimary)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
    }
}

private struct HermesHTMLPreview: UIViewRepresentable {
    let html: String
    let theme: IOSThemeTokens

    private var estimatedHeight: CGFloat {
        let explicitLines = html.components(separatedBy: .newlines).count
        let wrappedLines = max(explicitLines, html.count / 44)
        return min(420, max(180, CGFloat(wrappedLines * 18 + 86)))
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.showsHorizontalScrollIndicator = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(wrappedHTML, baseURL: nil)
    }

    private var wrappedHTML: String {
        let background = theme.isGeek ? "#111827" : "#ffffff"
        let foreground = theme.isGeek ? "#e5e7eb" : "#111827"
        let border = theme.isGeek ? "rgba(148, 163, 184, 0.28)" : "rgba(17, 24, 39, 0.12)"
        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
          <style>
            html, body {
              margin: 0;
              padding: 0;
              background: \(background);
              color: \(foreground);
              font: -apple-system-body;
              overflow-wrap: anywhere;
            }
            body {
              padding: 14px;
              border: 1px solid \(border);
              border-radius: 12px;
              box-sizing: border-box;
            }
            img, video, iframe, table {
              max-width: 100%;
            }
            button, input, select, textarea {
              font: inherit;
            }
          </style>
        </head>
        <body>
        \(html)
        </body>
        </html>
        """
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: WKWebView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 280, height: estimatedHeight)
    }
}

private enum HermesHTMLExtractor {
    static func extract(from source: String) -> String? {
        if let fenced = firstHTMLFence(in: source) {
            return fenced
        }

        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeHTML(trimmed) else { return nil }
        return trimmed
    }

    private static func firstHTMLFence(in source: String) -> String? {
        let lines = source.components(separatedBy: .newlines)
        var index = 0

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("```") else {
                index += 1
                continue
            }

            let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            index += 1
            var codeLines: [String] = []
            while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                codeLines.append(lines[index])
                index += 1
            }

            if language == "html" || language == "htm" {
                let html = codeLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                return html.isEmpty ? nil : html
            }

            index += 1
        }

        return nil
    }

    private static func looksLikeHTML(_ source: String) -> Bool {
        guard source.contains("<"), source.contains(">") else { return false }
        let lowercased = source.lowercased()
        let tags = ["<!doctype html", "<html", "<body", "<div", "<p", "<h1", "<h2", "<h3", "<ul", "<ol", "<li", "<table", "<button", "<style"]
        return tags.contains { lowercased.contains($0) }
    }
}

private struct IOSHermesPressToTalkTouchSurface: UIViewRepresentable {
    var onChanged: (CGSize) -> Void
    var onEnded: (CGSize) -> Void
    var onCancelled: () -> Void

    func makeUIView(context: Context) -> TouchView {
        let view = TouchView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = false
        return view
    }

    func updateUIView(_ uiView: TouchView, context: Context) {
        uiView.onChanged = onChanged
        uiView.onEnded = onEnded
        uiView.onCancelled = onCancelled
    }

    final class TouchView: UIView {
        var onChanged: ((CGSize) -> Void)?
        var onEnded: ((CGSize) -> Void)?
        var onCancelled: (() -> Void)?
        private var startLocation: CGPoint?

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = touches.first else { return }
            let location = touch.location(in: self)
            startLocation = location
            onChanged?(.zero)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = touches.first, let startLocation else { return }
            let location = touch.location(in: self)
            onChanged?(CGSize(width: location.x - startLocation.x, height: location.y - startLocation.y))
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = touches.first, let startLocation else {
                onEnded?(.zero)
                self.startLocation = nil
                return
            }
            let location = touch.location(in: self)
            onEnded?(CGSize(width: location.x - startLocation.x, height: location.y - startLocation.y))
            self.startLocation = nil
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            onCancelled?()
            startLocation = nil
        }
    }
}

private struct HermesTableView: View {
    let headers: [String]
    let rows: [[String]]
    let theme: IOSThemeTokens

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(headers.indices, id: \.self) { index in
                        tableCell(headers[index], isHeader: true)
                    }
                }

                ForEach(rows.indices, id: \.self) { rowIndex in
                    GridRow {
                        ForEach(0..<columnCount, id: \.self) { columnIndex in
                            tableCell(value(rowIndex: rowIndex, columnIndex: columnIndex), isHeader: false)
                        }
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.borderSubtle.opacity(0.9), lineWidth: 1)
            }
        }
    }

    private var columnCount: Int {
        max(headers.count, rows.map(\.count).max() ?? 0)
    }

    private func value(rowIndex: Int, columnIndex: Int) -> String {
        guard rows.indices.contains(rowIndex), rows[rowIndex].indices.contains(columnIndex) else { return "" }
        return rows[rowIndex][columnIndex]
    }

    private func tableCell(_ text: String, isHeader: Bool) -> some View {
        Text(text.isEmpty ? " " : text)
            .font(isHeader ? .caption.weight(.semibold) : .caption)
            .foregroundStyle(theme.textPrimary)
            .textSelection(.enabled)
            .frame(minWidth: 92, maxWidth: 180, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(isHeader ? theme.surfaceSecondary.opacity(0.8) : theme.surfacePrimary.opacity(0.45))
            .border(theme.borderSubtle.opacity(0.72), width: 0.5)
    }
}
