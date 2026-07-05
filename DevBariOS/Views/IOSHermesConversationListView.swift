import DevBarCore
import SwiftData
import SwiftUI

struct IOSHermesConversationListView: View {
    let provider: ChatBotProviderKind

    @EnvironmentObject private var appViewModel: IOSAppViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.themeTokens) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Query
    private var conversations: [IOSHermesConversation]

    @State private var destination: ChatDestination?
    @State private var isSettingsPresented = false
    @State private var isQuickStartManagerPresented = false
    @State private var quickStartItems: [HermesQuickStartItem] = []
    @State private var quickStartDraft: IOSHermesQuickStartDraft?
    @State private var hasRegisteredHermesInteraction = false
    @State private var isChatsCollapsed = false

    private let hermesSettingsStore = UserDefaultsHermesSettingsStore()

    init(provider: ChatBotProviderKind = .hermes) {
        self.provider = provider
        _conversations = Query(
            filter: #Predicate<IOSHermesConversation> { conversation in
                !conversation.isArchived
            },
            sort: \IOSHermesConversation.updatedAt,
            order: .reverse
        )
    }

    var body: some View {
        List {
            chatsSectionHeader
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 10, trailing: 16))

            if isChatsCollapsed {
                EmptyView()
            } else if displayedItems.isEmpty {
                emptyState
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 24, leading: 18, bottom: 0, trailing: 18))
            } else {
                ForEach(displayedItems) { item in
                    Button {
                        open(item)
                    } label: {
                        conversationRow(item)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            delete(item)
                        } label: {
                            Label("ios_common_delete", systemImage: "trash")
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                }
            }

            if isChatsCollapsed || !displayedItems.isEmpty {
                quickStartSection
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 18, leading: 16, bottom: 16, trailing: 16))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(hermesPageBackground.ignoresSafeArea())
        .navigationTitle(provider.toolTitle)
        .toolbarTitleDisplayMode(.inlineLarge)
        .iosToolNavigationChrome(theme)
        .toolbarBackground(hermesPageBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(theme.isGeek || colorScheme == .dark ? .dark : .light, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    destination = ChatDestination(
                        id: "new.\(UUID().uuidString)",
                        kind: .new,
                        settings: appViewModel.hermesSettings,
                        apiKey: appViewModel.hermesAPIKey
                    )
                } label: {
                    Image(systemName: "square.and.pencil")
                        .iosToolToolbarIcon(theme)
                }
                .accessibilityIdentifier("ios.hermes.conversation.new")

                Button {
                    isSettingsPresented = true
                } label: {
                    Image(systemName: "ellipsis")
                        .iosToolToolbarIcon(theme)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ios.hermes.conversation.settings")
            }
        }
        .navigationDestination(isPresented: $isSettingsPresented) {
            IOSHermesChatSettingsView(
                provider: provider,
                remark: remarkBinding,
                tag: tagBinding,
                theme: theme
            )
        }
        .navigationDestination(isPresented: chatDestinationPresentedBinding) {
            chatDestinationView
        }
        .sheet(isPresented: $isQuickStartManagerPresented) {
            IOSHermesQuickStartManagerView(
                items: quickStartItems,
                defaultItems: defaultQuickStartItems
            ) { items in
                saveQuickStartItems(items)
            }
        }
        .sheet(item: $quickStartDraft) { draft in
            IOSHermesQuickStartEditView(draft: draft) { savedDraft in
                saveQuickStartDraft(savedDraft)
            }
        }
        .onAppear {
            registerHermesInteractionIfNeeded()
            loadQuickStartItems()
        }
        .onDisappear {
            unregisterHermesInteractionIfNeeded()
        }
        .accessibilityIdentifier("ios.hermes.conversation.list")
    }

    private var chatsSectionHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isChatsCollapsed.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "message")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(theme.textPrimary)
                    .frame(width: 22, height: 22)

                Text("Chats")
                    .font(theme.appFont.font(.title3, weight: .semibold, monospaced: theme.isGeek))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
                    .rotationEffect(.degrees(isChatsCollapsed ? -90 : 0))

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Chats")
        .accessibilityValue(isChatsCollapsed ? "Collapsed" : "Expanded")
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 40)
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(theme.textSecondary.opacity(0.58))
            VStack(spacing: 6) {
                Text("ios_hermes_empty_title")
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                Text("ios_hermes_empty_subtitle")
                    .font(theme.footnoteFont)
                    .foregroundStyle(theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            quickStartSection
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 560)
    }

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.sparkles.inverse")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
                    .frame(width: 18, height: 18)

                Text("ios_hermes_quick_start_title")
                    .font(theme.captionWeightFont)
                    .foregroundStyle(theme.textTertiary)
                    .textCase(.uppercase)

                Spacer(minLength: 0)

                Button {
                    isQuickStartManagerPresented = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.textTertiary)
                        .frame(width: 30, height: 30)
                        .background(theme.surfacePrimary.opacity(theme.isGeek ? 0.58 : 0.86), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ios_hermes_quick_manage")
            }

            if quickStartItems.isEmpty {
                Button {
                    isQuickStartManagerPresented = true
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("ios_hermes_quick_empty_title")
                                .font(theme.footnoteFont.weight(.semibold))
                                .foregroundStyle(theme.textPrimary)
                            Text("ios_hermes_quick_empty_subtitle")
                                .font(theme.captionFont)
                                .foregroundStyle(theme.textTertiary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(theme.surfacePrimary.opacity(theme.isGeek ? 0.62 : 0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(theme.borderSubtle.opacity(theme.isGeek ? 0.34 : 0.14), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 8) {
                    ForEach(quickStartItems) { item in
                        quickStartRow(item)
                    }
                }
            }
        }
    }

    private var displayedItems: [HermesConversationListItem] {
        Self.deduplicatedLocalConversations(conversations.filter(Self.matchesHermesProvider))
            .map(HermesConversationListItem.local)
    }

    private var hermesPageBackground: Color {
        theme.isGeek || colorScheme == .dark ? .black : theme.backgroundSecondary
    }

    private func conversationRow(_ item: HermesConversationListItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(item.title(fallback: String(localized: "ios_hermes_conversation_untitled")))
                        .font(theme.bodyFont.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(relativeTimeString(for: item.updatedAt(default: Date())))
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textTertiary)
                }

                Text(item.preview.isEmpty ? String(localized: "ios_hermes_conversation_new") : item.preview)
                    .font(theme.footnoteFont)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(theme.surfacePrimary.opacity(theme.isGeek ? 0.72 : 0.94), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(theme.borderSubtle.opacity(theme.isGeek ? 0.42 : 0.16), lineWidth: 1)
        }
    }

    private func open(_ item: HermesConversationListItem) {
        switch item {
        case .local(let conversation):
            let start = CFAbsoluteTimeGetCurrent()
            debugLog("open tap local id=\(conversation.id.uuidString) messages=\(conversation.messages.count)")
            let snapshot = IOSHermesChatViewModel.messageSnapshot(in: conversation)
            debugLog("open snapshot ready local id=\(conversation.id.uuidString) count=\(snapshot.count) dt=\(elapsedMilliseconds(since: start))ms")
            destination = ChatDestination(
                id: "conversation.\(conversation.id.uuidString)",
                kind: .conversation(conversation, snapshot),
                settings: appViewModel.hermesSettings,
                apiKey: appViewModel.hermesAPIKey
            )
            debugLog("open destination set local id=\(conversation.id.uuidString) dt=\(elapsedMilliseconds(since: start))ms")
        }
    }

    private var chatDestinationPresentedBinding: Binding<Bool> {
        Binding {
            destination != nil
        } set: { isPresented in
            if !isPresented {
                destination = nil
            }
        }
    }

    @ViewBuilder
    private var chatDestinationView: some View {
        if let destination {
            let start = CFAbsoluteTimeGetCurrent()
            switch destination.kind {
            case .new:
                IOSHermesChatView(
                    provider: provider,
                    initialSettings: destination.settings,
                    initialAPIKey: destination.apiKey
                )
                .onAppear {
                    debugLog("destination appear id=\(destination.id) dt=\(elapsedMilliseconds(since: start))ms")
                }
            case .conversation(let conversation, let messages):
                IOSHermesChatView(
                    provider: provider,
                    conversation: conversation,
                    initialMessages: messages,
                    initialSettings: destination.settings,
                    initialAPIKey: destination.apiKey
                )
                .onAppear {
                    debugLog("destination appear id=\(destination.id) dt=\(elapsedMilliseconds(since: start))ms")
                }
            case .quickStart(let prompt):
                IOSHermesChatView(
                    provider: provider,
                    initialSettings: destination.settings,
                    initialAPIKey: destination.apiKey,
                    initialDraft: prompt
                )
                .onAppear {
                    debugLog("destination appear id=\(destination.id) dt=\(elapsedMilliseconds(since: start))ms")
                }
            }
        } else {
            EmptyView()
        }
    }

    private func registerHermesInteractionIfNeeded() {
        guard !hasRegisteredHermesInteraction else { return }
        hasRegisteredHermesInteraction = true
        if !appViewModel.claimHermesChatInteractionReservation(reason: "conversation list appear") {
            appViewModel.beginHermesChatInteraction(reason: "conversation list appear")
        }
    }

    private func unregisterHermesInteractionIfNeeded() {
        guard hasRegisteredHermesInteraction else { return }
        guard !isNavigatingInsideHermes else {
            debugLog("keep interaction for internal navigation destination=\(destination?.id ?? "-") settings=\(isSettingsPresented)")
            return
        }
        hasRegisteredHermesInteraction = false
        appViewModel.endHermesChatInteraction()
    }

    private var isNavigatingInsideHermes: Bool {
        destination != nil || isSettingsPresented
    }

    private func quickStartRow(_ item: HermesQuickStartItem) -> some View {
        Button {
            destination = ChatDestination(
                id: "quickStart.\(UUID().uuidString)",
                kind: .quickStart(item.prompt),
                settings: appViewModel.hermesSettings,
                apiKey: appViewModel.hermesAPIKey
            )
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(theme.footnoteFont.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(item.subtitle.isEmpty ? item.prompt : item.subtitle)
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(12)
            .background(theme.surfacePrimary.opacity(theme.isGeek ? 0.62 : 0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(theme.borderSubtle.opacity(theme.isGeek ? 0.34 : 0.14), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                quickStartDraft = IOSHermesQuickStartDraft(item: item)
            } label: {
                Label("ios_hermes_quick_edit", systemImage: "pencil")
            }

            Button {
                duplicateQuickStartItem(item)
            } label: {
                Label("ios_hermes_quick_duplicate", systemImage: "plus.square.on.square")
            }

            Button(role: .destructive) {
                deleteQuickStartItem(item)
            } label: {
                Label("ios_common_delete", systemImage: "trash")
            }
        }
    }

    private var providerRemark: String {
        appViewModel.hermesSettings.chatRemark(for: provider)
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

    private var defaultQuickStartItems: [HermesQuickStartItem] {
        [
            HermesQuickStartItem(
                id: Self.quickErrorID,
                title: String(localized: "ios_hermes_quick_error_title"),
                subtitle: String(localized: "ios_hermes_quick_error_subtitle"),
                systemImage: "exclamationmark.magnifyingglass",
                prompt: String(localized: "ios_hermes_quick_error_prompt")
            ),
            HermesQuickStartItem(
                id: Self.quickContextID,
                title: String(localized: "ios_hermes_quick_context_title"),
                subtitle: String(localized: "ios_hermes_quick_context_subtitle"),
                systemImage: "text.badge.checkmark",
                prompt: String(localized: "ios_hermes_quick_context_prompt")
            ),
            HermesQuickStartItem(
                id: Self.quickPlanID,
                title: String(localized: "ios_hermes_quick_plan_title"),
                subtitle: String(localized: "ios_hermes_quick_plan_subtitle"),
                systemImage: "checklist",
                prompt: String(localized: "ios_hermes_quick_plan_prompt")
            )
        ]
    }

    private func loadQuickStartItems() {
        quickStartItems = hermesSettingsStore.loadQuickStartItems(defaults: defaultQuickStartItems)
    }

    private func saveQuickStartItems(_ items: [HermesQuickStartItem]) {
        let normalizedItems = items.compactMap(\.normalized)
        quickStartItems = normalizedItems
        hermesSettingsStore.saveQuickStartItems(normalizedItems)
    }

    private func saveQuickStartDraft(_ draft: IOSHermesQuickStartDraft) {
        guard let item = draft.item else { return }
        var updatedItems = quickStartItems
        if let originalID = draft.originalID,
           let existingIndex = updatedItems.firstIndex(where: { $0.id == originalID }) {
            updatedItems[existingIndex] = item
        } else {
            updatedItems.append(item)
        }
        saveQuickStartItems(updatedItems)
    }

    private func duplicateQuickStartItem(_ item: HermesQuickStartItem) {
        var duplicated = item
        duplicated.id = UUID()
        saveQuickStartItems(quickStartItems + [duplicated])
    }

    private func deleteQuickStartItem(_ item: HermesQuickStartItem) {
        saveQuickStartItems(quickStartItems.filter { $0.id != item.id })
    }

    private func relativeTimeString(for date: Date) -> String {
        let elapsed = max(0, Int(Date().timeIntervalSince(date)))
        if Locale.autoupdatingCurrent.language.languageCode?.identifier == "zh" {
            if elapsed < 60 { return String(localized: "ios_hermes_time_now") }
            if elapsed < 3600 {
                return String(format: String(localized: "ios_hermes_time_minutes_ago"), elapsed / 60)
            }
            if elapsed < 86400 {
                return String(format: String(localized: "ios_hermes_time_hours_ago"), elapsed / 3600)
            }
            if elapsed < 172800 { return String(localized: "ios_hermes_time_yesterday") }
        }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func delete(_ item: HermesConversationListItem) {
        switch item {
        case .local(let conversation):
            withAnimation(.easeInOut(duration: 0.18)) {
                archive(conversation)
            }
        }
    }

    private func archive(_ conversation: IOSHermesConversation) {
        conversation.isArchived = true
        conversation.archivedAt = Date()
        conversation.updatedAt = Date()
        try? modelContext.save()
    }

    private func debugLog(_ message: String) {
        IOSDebugLogger.log("HermesSessions", message)
    }

    private func elapsedMilliseconds(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1_000)
    }

    @MainActor
    private static func matchesHermesProvider(_ conversation: IOSHermesConversation) -> Bool {
        conversation.providerRawValue == ChatBotProviderKind.hermes.rawValue ||
            conversation.providerRawValue == nil ||
            conversation.providerRawValue == "customProvider"
    }

    @MainActor
    private static func deduplicatedLocalConversations(_ conversations: [IOSHermesConversation]) -> [IOSHermesConversation] {
        var conversationsWithoutRemoteSession: [IOSHermesConversation] = []
        var bestConversationBySessionID: [String: IOSHermesConversation] = [:]

        for conversation in conversations {
            guard let sessionID = conversation.remoteSessionId?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty else {
                conversationsWithoutRemoteSession.append(conversation)
                continue
            }
            guard let current = bestConversationBySessionID[sessionID] else {
                bestConversationBySessionID[sessionID] = conversation
                continue
            }
            bestConversationBySessionID[sessionID] = preferredConversation(current, conversation)
        }

        return (conversationsWithoutRemoteSession + Array(bestConversationBySessionID.values))
            .sorted(by: conversationSortOrder)
    }

    @MainActor
    private static func preferredConversation(_ lhs: IOSHermesConversation, _ rhs: IOSHermesConversation) -> IOSHermesConversation {
        if lhs.messageCount != rhs.messageCount {
            return lhs.messageCount > rhs.messageCount ? lhs : rhs
        }
        if lhs.messages.count != rhs.messages.count {
            return lhs.messages.count > rhs.messages.count ? lhs : rhs
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt ? lhs : rhs
        }
        return lhs.createdAt <= rhs.createdAt ? lhs : rhs
    }

    @MainActor
    private static func conversationSortOrder(_ lhs: IOSHermesConversation, _ rhs: IOSHermesConversation) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private static let quickErrorID = UUID(uuidString: "5C295E94-4B2F-432D-A413-6742ADCEB961")!
    private static let quickContextID = UUID(uuidString: "D3BD5118-421C-46EB-B22C-2E63827E7F56")!
    private static let quickPlanID = UUID(uuidString: "4C9B6B2F-D663-4D96-A24C-05FBC4A81315")!
}

private struct ChatDestination: Identifiable {
    enum Kind {
        case new
        case conversation(IOSHermesConversation, [IOSHermesChatViewModel.Message])
        case quickStart(String)
    }

    let id: String
    let kind: Kind
    let settings: HermesSettings
    let apiKey: String
}

private enum HermesConversationListItem: Identifiable {
    case local(IOSHermesConversation)

    var id: String {
        switch self {
        case .local(let conversation):
            return "local.\(conversation.id.uuidString)"
        }
    }

    var preview: String {
        switch self {
        case .local(let conversation):
            return conversation.lastMessagePreview
        }
    }

    var messageCount: Int {
        switch self {
        case .local(let conversation):
            return conversation.messageCount
        }
    }

    func title(fallback: String) -> String {
        let rawTitle: String
        switch self {
        case .local(let conversation):
            if let firstUserMessageTitle = conversation.firstUserMessageTitle {
                return firstUserMessageTitle
            }
            rawTitle = conversation.title
        }
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? fallback : title
    }

    func updatedAt(default defaultDate: Date) -> Date {
        switch self {
        case .local(let conversation):
            return conversation.updatedAt
        }
    }
}

private struct IOSHermesQuickStartDraft: Identifiable, Equatable {
    var id: UUID
    var originalID: UUID?
    var title: String
    var subtitle: String
    var systemImage: String
    var prompt: String

    init(item: HermesQuickStartItem) {
        id = item.id
        originalID = item.id
        title = item.title
        subtitle = item.subtitle
        systemImage = item.systemImage
        prompt = item.prompt
    }

    init() {
        id = UUID()
        originalID = nil
        title = ""
        subtitle = ""
        systemImage = "sparkles"
        prompt = ""
    }

    var item: HermesQuickStartItem? {
        HermesQuickStartItem(
            id: id,
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            prompt: prompt
        ).normalized
    }
}

private struct IOSHermesQuickStartManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeTokens) private var theme
    @Environment(\.colorScheme) private var colorScheme

    @State private var items: [HermesQuickStartItem]
    @State private var draft: IOSHermesQuickStartDraft?

    let defaultItems: [HermesQuickStartItem]
    let onSave: ([HermesQuickStartItem]) -> Void

    init(
        items: [HermesQuickStartItem],
        defaultItems: [HermesQuickStartItem],
        onSave: @escaping ([HermesQuickStartItem]) -> Void
    ) {
        _items = State(initialValue: items)
        self.defaultItems = defaultItems
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    ContentUnavailableView(
                        "ios_hermes_quick_empty_title",
                        systemImage: "sparkles",
                        description: Text("ios_hermes_quick_empty_subtitle")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(items) { item in
                        quickStartManagementRow(item)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    delete(item)
                                } label: {
                                    Label("ios_common_delete", systemImage: "trash")
                                }
                            }
                    }
                    .onMove(perform: move)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(quickStartBackground.ignoresSafeArea())
            .navigationTitle("ios_hermes_quick_manage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(quickStartBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(theme.isGeek || colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ios_common_cancel") {
                        dismiss()
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        items = defaultItems
                        persist()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .accessibilityLabel("ios_hermes_quick_restore_defaults")

                    Button {
                        draft = IOSHermesQuickStartDraft()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("ios_hermes_quick_add")

                    EditButton()

                    Button("ios_common_done") {
                        persist()
                        dismiss()
                    }
                    .font(.headline.weight(.semibold))
                }
            }
            .sheet(item: $draft) { draft in
                IOSHermesQuickStartEditView(draft: draft) { savedDraft in
                    save(savedDraft)
                }
            }
        }
    }

    private var quickStartBackground: Color {
        theme.isGeek || colorScheme == .dark ? .black : theme.backgroundSecondary
    }

    private func quickStartManagementRow(_ item: HermesQuickStartItem) -> some View {
        Button {
            draft = IOSHermesQuickStartDraft(item: item)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.brandPrimary)
                    .frame(width: 34, height: 34)
                    .background(theme.brandPrimary.opacity(theme.isGeek ? 0.18 : 0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(theme.bodyFont.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(item.subtitle.isEmpty ? item.prompt : item.subtitle)
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func save(_ draft: IOSHermesQuickStartDraft) {
        guard let item = draft.item else { return }
        if let originalID = draft.originalID,
           let existingIndex = items.firstIndex(where: { $0.id == originalID }) {
            items[existingIndex] = item
        } else {
            items.append(item)
        }
        persist()
    }

    private func delete(_ item: HermesQuickStartItem) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    private func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    private func persist() {
        onSave(items)
    }
}

private struct IOSHermesQuickStartEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeTokens) private var theme
    @Environment(\.colorScheme) private var colorScheme

    @State private var draft: IOSHermesQuickStartDraft

    let onSave: (IOSHermesQuickStartDraft) -> Void

    init(
        draft: IOSHermesQuickStartDraft,
        onSave: @escaping (IOSHermesQuickStartDraft) -> Void
    ) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("ios_hermes_quick_title_field", text: $draft.title)
                    TextField("ios_hermes_quick_subtitle_field", text: $draft.subtitle)
                    TextField("ios_hermes_quick_icon_field", text: $draft.systemImage)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("ios_hermes_quick_prompt_field") {
                    TextEditor(text: $draft.prompt)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 160)
                }
            }
            .scrollContentBackground(.hidden)
            .background(quickStartBackground.ignoresSafeArea())
            .navigationTitle(draft.originalID == nil ? "ios_hermes_quick_add" : "ios_hermes_quick_edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(quickStartBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(theme.isGeek || colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ios_common_cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("ios_common_done") {
                        onSave(draft)
                        dismiss()
                    }
                    .font(.headline.weight(.semibold))
                    .disabled(draft.item == nil)
                }
            }
        }
    }

    private var quickStartBackground: Color {
        theme.isGeek || colorScheme == .dark ? .black : theme.backgroundSecondary
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
