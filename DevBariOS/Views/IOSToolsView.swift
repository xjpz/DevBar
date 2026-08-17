import DevBarCore
import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

struct IOSToolsView: View {
    @EnvironmentObject private var appViewModel: IOSAppViewModel
    @Environment(\.themeTokens) private var theme
    @State private var toolOrder = IOSToolOrderStore().load()
    @State private var hiddenToolIDs = IOSToolVisibilityStore().load()
    @State private var draggedToolID: String?
    @State private var editMode: IOSToolsEditMode?
    @State private var toastMessage: String?

    private let orderStore = IOSToolOrderStore()
    private let visibilityStore = IOSToolVisibilityStore()

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ZStack {
            ScrollView {
                toolsContent
            }
            .background(toolsPageBackground.ignoresSafeArea())

            if let toastMessage {
                IOSStatusToast(toastMessage, kind: .failure, theme: theme)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .navigationTitle("ios_tab_tools")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbarBackground(toolsNavigationBackground, for: .navigationBar)
        .toolbarBackground(theme.isGeek ? .visible : .hidden, for: .navigationBar)
        .toolbarColorScheme(theme.isGeek ? .dark : nil, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if editMode != nil {
                    Button("ios_common_done") {
                        endEditing()
                    }
                } else {
                    Menu {
                        Button {
                            beginEditing(.sort)
                        } label: {
                            Label("排序", systemImage: "arrow.up.arrow.down")
                        }

                        Button {
                            beginEditing(.pinTabs)
                        } label: {
                            Label("固定", systemImage: "pin")
                        }

                        Button {
                            beginEditing(.visibility)
                        } label: {
                            Label("ios_tools_visibility_manage", systemImage: "eye")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .iosToolToolbarIcon(theme)
                    }
                    .accessibilityLabel("更多工具操作")
                }
            }
        }
        .accessibilityIdentifier("ios.tools.screen")
    }

    private var toolsPageBackground: Color {
        theme.isGeek ? .black : theme.backgroundSecondary
    }

    private var toolsNavigationBackground: Color {
        theme.isGeek ? .black : .clear
    }

    @ViewBuilder
    private var toolsContent: some View {
        if isManagingVisibility {
            visibilityManagementContent
        } else if visibleTools.isEmpty {
            ContentUnavailableView {
                Label("ios_tools_visibility_empty_title", systemImage: "eye.slash")
            } description: {
                Text("ios_tools_visibility_empty_detail")
            } actions: {
                Button("ios_tools_visibility_manage") {
                    beginEditing(.visibility)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("ios.tools.visibility.manageEmptyState")
            }
            .frame(maxWidth: .infinity, minHeight: 420)
            .padding(16)
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(visibleTools) { tool in
                    toolGridItem(tool)
                }
            }
            .padding(16)
        }
    }

    private var orderedTools: [IOSToolDefinition] {
        let tools = IOSToolCatalog.availableTools()
        let toolByID = Dictionary(uniqueKeysWithValues: tools.map { ($0.id, $0) })
        let orderedIDs = IOSToolOrder.resolvedOrder(
            savedOrder: toolOrder,
            defaultOrder: tools.map(\.id)
        )

        return orderedIDs.compactMap { toolByID[$0] }
    }

    private var resolvedHiddenToolIDs: [String] {
        IOSToolVisibility.resolvedHiddenIDs(
            savedHiddenIDs: hiddenToolIDs,
            availableIDs: orderedTools.map(\.id)
        )
    }

    private var visibleTools: [IOSToolDefinition] {
        let hiddenIDSet = Set(resolvedHiddenToolIDs)
        return orderedTools.filter { !hiddenIDSet.contains($0.id) }
    }

    private var hiddenTools: [IOSToolDefinition] {
        let hiddenIDSet = Set(resolvedHiddenToolIDs)
        return orderedTools.filter { hiddenIDSet.contains($0.id) }
    }

    private var pinnableToolIDs: [String] {
        IOSToolCatalog.availableTools()
            .filter(\.isPinnedTabEligible)
            .map(\.id)
    }

    @ViewBuilder
    private func toolGridItem(_ tool: IOSToolDefinition) -> some View {
        if editMode == nil || isReordering {
            reorderableToolGridItem(tool)
        } else {
            toolGridItemContent(tool)
                .buttonStyle(.plain)
                .animation(.spring(response: 0.28, dampingFraction: 0.86), value: visibleTools.map(\.id))
        }
    }

    @ViewBuilder
    private func toolGridItemContent(_ tool: IOSToolDefinition) -> some View {
        Group {
            if isReordering {
                toolCard(tool)
            } else if isPinningTabs {
                ZStack(alignment: .topTrailing) {
                    toolCard(tool)

                    if tool.isPinnedTabEligible {
                        pinButton(for: tool)
                            .padding(8)
                    }
                }
            } else {
                NavigationLink {
                    IOSToolDestinationView(toolID: tool.id)
                } label: {
                    toolCard(tool)
                }
                .simultaneousGesture(
                    TapGesture().onEnded {
                        prepareForOpeningTool(tool)
                    }
                )
            }
        }
    }

    private func reorderableToolGridItem(_ tool: IOSToolDefinition) -> some View {
        toolGridItemContent(tool)
        .buttonStyle(.plain)
        .scaleEffect(draggedToolID == tool.id ? 0.96 : 1)
        .opacity(draggedToolID == tool.id ? 0.72 : 1)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35)
                .onEnded { _ in
                    beginEditing(.sort)
                }
        )
        .onDrag {
            beginEditing(.sort)
            draggedToolID = tool.id
            return NSItemProvider(object: tool.id as NSString)
        }
        .onDrop(
            of: [UTType.plainText],
            delegate: IOSToolDropDelegate(
                targetID: tool.id,
                draggedToolID: $draggedToolID,
                isReordering: isReorderingBinding,
                move: moveTool
            )
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: visibleTools.map(\.id))
    }

    private func toolCard(_ tool: IOSToolDefinition, statusText: String? = nil) -> some View {
        IOSToolCard(
            title: tool.title,
            subtitle: tool.subtitle,
            systemImage: tool.systemImage,
            iconColor: tool.iconColor,
            theme: theme,
            isReordering: isReordering,
            statusText: statusText
        )
    }

    private var visibilityManagementContent: some View {
        LazyVStack(alignment: .leading, spacing: 20) {
            visibilitySectionHeader(
                title: String(localized: "ios_tools_visibility_visible_section"),
                count: visibleTools.count
            )

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(visibleTools) { tool in
                    visibilityGridItem(tool, isHidden: false)
                }
            }

            visibilitySectionHeader(
                title: String(localized: "ios_tools_visibility_hidden_section"),
                count: hiddenTools.count
            )

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(hiddenTools) { tool in
                    visibilityGridItem(tool, isHidden: true)
                }
            }
        }
        .padding(16)
        .accessibilityIdentifier("ios.tools.visibility.sections")
    }

    private func visibilitySectionHeader(title: String, count: Int) -> some View {
        Text(verbatim: "\(title) \(count)")
            .font(.headline.weight(.semibold))
            .foregroundStyle(theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private func visibilityGridItem(_ tool: IOSToolDefinition, isHidden: Bool) -> some View {
        let isPinned = appViewModel.isToolPinnedToTab(tool.id, availableToolIDs: pinnableToolIDs)
        let statusText = isHidden && isPinned
            ? String(localized: "ios_tools_visibility_pinned")
            : nil

        return ZStack(alignment: .topTrailing) {
            toolCard(tool, statusText: statusText)
                .opacity(isHidden ? 0.62 : 1)

            visibilityButton(for: tool, isHidden: isHidden)
                .padding(2)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: resolvedHiddenToolIDs)
    }

    private func visibilityButton(for tool: IOSToolDefinition, isHidden: Bool) -> some View {
        let labelFormat = isHidden
            ? String(localized: "ios_tools_visibility_show_on_page")
            : String(localized: "ios_tools_visibility_hide_from_page")

        return Button {
            if isHidden {
                showTool(tool.id)
            } else {
                hideTool(tool.id)
            }
        } label: {
            Image(systemName: isHidden ? "eye" : "eye.slash")
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isHidden ? theme.brandPrimary : theme.textSecondary)
                .frame(width: 32, height: 32)
                .background(theme.surfaceSecondary.opacity(0.88), in: Circle())
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(String(format: labelFormat, tool.title)))
        .accessibilityIdentifier("ios.tools.visibility.\(isHidden ? "show" : "hide").\(tool.id)")
    }

    private var isReordering: Bool {
        editMode == .sort
    }

    private var isPinningTabs: Bool {
        editMode == .pinTabs
    }

    private var isManagingVisibility: Bool {
        editMode == .visibility
    }

    private var isReorderingBinding: Binding<Bool> {
        Binding(
            get: { isReordering },
            set: { isEnabled in
                if isEnabled {
                    beginEditing(.sort)
                } else if isReordering {
                    endEditing()
                }
            }
        )
    }

    private func pinButton(for tool: IOSToolDefinition) -> some View {
        let isPinned = appViewModel.isToolPinnedToTab(tool.id, availableToolIDs: pinnableToolIDs)
        let canAdd = appViewModel.canPinMoreTools(availableToolIDs: pinnableToolIDs)

        return Button {
            if isPinned {
                appViewModel.removePinnedToolTab(tool.id, availableToolIDs: pinnableToolIDs)
            } else if canAdd {
                appViewModel.addPinnedToolTab(tool.id, availableToolIDs: pinnableToolIDs)
            } else {
                showToast("最多添加 3 个")
            }
        } label: {
            Image(systemName: isPinned ? "checkmark.circle.fill" : "plus.circle")
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isPinned ? theme.brandPrimary : (canAdd ? theme.textSecondary : theme.textTertiary))
                .frame(width: 32, height: 32)
                .background(theme.surfaceSecondary.opacity(0.88), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPinned ? "Remove from bottom tab" : "Add to bottom tab")
    }

    private func moveTool(_ sourceID: String, _ targetID: String) {
        let fullOrder = orderedTools.map(\.id)
        let currentVisibleOrder = visibleTools.map(\.id)
        let updatedVisibleOrder = IOSToolOrder.moving(sourceID, before: targetID, in: currentVisibleOrder)

        guard updatedVisibleOrder != currentVisibleOrder else { return }

        let updatedFullOrder = IOSToolVisibility.mergingVisibleOrder(
            updatedVisibleOrder,
            into: fullOrder,
            hiddenIDs: resolvedHiddenToolIDs
        )
        toolOrder = updatedFullOrder
        orderStore.save(updatedFullOrder)
    }

    private func hideTool(_ id: String) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            hiddenToolIDs = IOSToolVisibility.hiding(id, in: hiddenToolIDs)
            visibilityStore.save(hiddenToolIDs)
        }
    }

    private func showTool(_ id: String) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            hiddenToolIDs = IOSToolVisibility.showing(id, in: hiddenToolIDs)
            visibilityStore.save(hiddenToolIDs)
        }
    }

    private func beginEditing(_ mode: IOSToolsEditMode) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            editMode = mode
            if mode != .sort {
                draggedToolID = nil
            }
        }
    }

    private func endEditing() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            editMode = nil
            draggedToolID = nil
        }
    }

    private func showToast(_ message: String) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            toastMessage = message
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            guard toastMessage == message else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                toastMessage = nil
            }
        }
    }

    private func prepareForOpeningTool(_ tool: IOSToolDefinition) {
        guard tool.id == "chatbot-hermes" else { return }
        appViewModel.reserveHermesChatInteraction(reason: "tools grid tap")
    }
}

private enum IOSToolsEditMode {
    case sort
    case pinTabs
    case visibility
}

struct IOSToolCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let iconColor: Color
    let theme: IOSThemeTokens
    var isReordering = false
    var statusText: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(iconColor.opacity(0.12))
                .frame(width: 42, height: 42)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(iconColor)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(subtitle)
                    .font(.subheadline.weight(.regular))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if let statusText {
                    Text(statusText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            if isReordering {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .iosGlassContainer(theme, cornerRadius: 18)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(theme.borderSubtle, lineWidth: 1)
        )
    }
}

struct IOSToolDefinition: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let iconColor: Color
    var tabTitle: String
    var isPinnedTabEligible: Bool

    init(
        id: String,
        title: String,
        subtitle: String,
        systemImage: String,
        iconColor: Color,
        tabTitle: String? = nil,
        isPinnedTabEligible: Bool = true
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.iconColor = iconColor
        self.tabTitle = tabTitle ?? title
        self.isPinnedTabEligible = isPinnedTabEligible
    }
}

enum IOSToolCatalog {
    static func availableTools() -> [IOSToolDefinition] {
        var tools: [IOSToolDefinition] = [
            IOSToolDefinition(id: "api-client", title: "API 调试", subtitle: "API Client", systemImage: "globe", iconColor: .cyan, tabTitle: "API"),
            IOSToolDefinition(id: "formatter", title: "格式化", subtitle: "Formatter", systemImage: "curlybraces", iconColor: .yellow),
            IOSToolDefinition(id: "base64", title: "Base64", subtitle: "编码 / 解码", systemImage: "lock.square", iconColor: .indigo),
            IOSToolDefinition(id: "timestamp", title: "时间戳", subtitle: "Timestamp", systemImage: "clock", iconColor: .mint),
            IOSToolDefinition(id: "markdown", title: "Markdown", subtitle: "编辑 / 预览", systemImage: "doc.richtext", iconColor: .orange),
            IOSToolDefinition(id: "qr-code", title: "二维码", subtitle: "QR Code", systemImage: "qrcode", iconColor: .blue, tabTitle: "QR"),
            IOSToolDefinition(id: "mac-relay", title: "Mac 中继", subtitle: "Relay", systemImage: "macbook.and.iphone", iconColor: .green, tabTitle: "Relay"),
            IOSToolDefinition(id: "terminal", title: "终端", subtitle: "Terminal", systemImage: "terminal.fill", iconColor: .green, tabTitle: "Terminal"),
        ]

        if #available(iOS 18.0, *) {
            tools.append(IOSToolDefinition(id: "webkit", title: "WebKit", subtitle: "Browser", systemImage: "globe", iconColor: .blue))
            tools.append(IOSToolDefinition(id: "translation", title: "翻译", subtitle: "Translate", systemImage: "character.book.closed", iconColor: .teal))
        }

        tools.append(contentsOf: [
            IOSToolDefinition(id: "ocr", title: "文字识别", subtitle: "OCR", systemImage: "doc.text.viewfinder", iconColor: .purple, tabTitle: "OCR"),
            IOSToolDefinition(id: "speech-to-text", title: "语音转文字", subtitle: "Speech to Text", systemImage: "mic.fill", iconColor: .pink, tabTitle: "Speech"),
            IOSToolDefinition(id: "memo", title: "备忘录", subtitle: "Memo", systemImage: "note.text", iconColor: .brown, tabTitle: "Memo"),
            IOSToolDefinition(id: "chatbot-hermes", title: "Hermes", subtitle: "ChatBot", systemImage: "bubble.left.and.bubble.right.fill", iconColor: .green, tabTitle: "Hermes"),
            IOSToolDefinition(id: "home-assistant", title: "Home Assistant", subtitle: "家庭控制台", systemImage: "apple.homekit", iconColor: .blue, tabTitle: "家庭"),
        ])

        return tools
    }
}

struct IOSToolDestinationView: View {
    @Environment(\.themeTokens) private var theme

    let toolID: String
    var entryContext: IOSToolEntryContext = .pushed

    var body: some View {
        Group {
            switch toolID {
            case "api-client":
                IOSAPIClientView()
            case "formatter":
                IOSFormatterView()
            case "base64":
                IOSBase64View()
            case "timestamp":
                IOSTimestampView()
            case "markdown":
                IOSMarkdownView()
            case "qr-code":
                IOSQRCodeView()
            case "mac-relay":
                IOSMacRelayView()
            case "terminal":
                IOSTerminalServerListView()
            case "webkit":
                if #available(iOS 18.0, *) {
                    IOSWebKitView()
                } else {
                    ContentUnavailableView("Requires iOS 18+", systemImage: "globe")
                }
            case "translation":
                if #available(iOS 18.0, *) {
                    IOSTranslationView()
                } else {
                    EmptyView()
                }
            case "ocr":
                IOSOCRView()
            case "speech-to-text":
                IOSSpeechToTextView()
            case "memo":
                IOSMemoListView()
            case "chatbot-hermes":
                IOSHermesConversationListView(provider: .hermes)
            case "home-assistant":
                IOSHomeAssistantDashboardView()
            default:
                EmptyView()
            }
        }
        .environment(\.iosToolEntryContext, entryContext)
        .toolbar(entryContext.tabBarVisibility, for: .tabBar)
        .toolbarTitleDisplayMode(entryContext.toolbarTitleDisplayMode)
        .toolbarBackground(toolNavigationBackground, for: .navigationBar)
        .toolbarBackground(toolNavigationBackgroundVisibility, for: .navigationBar)
        .toolbarColorScheme(theme.isGeek ? .dark : nil, for: .navigationBar)
    }

    private var toolNavigationBackground: Color {
        theme.isGeek ? .black : .clear
    }

    private var toolNavigationBackgroundVisibility: Visibility {
        theme.isGeek && toolID != "home-assistant" ? .visible : .hidden
    }
}

enum IOSToolEntryContext {
    case pushed
    case tabRoot

    var showsBackButton: Bool {
        self == .pushed
    }

    var tabBarVisibility: Visibility {
        self == .tabRoot ? .visible : .hidden
    }

    var toolbarTitleDisplayMode: ToolbarTitleDisplayMode {
        self == .tabRoot ? .inlineLarge : .inline
    }
}

private struct IOSToolTitleDisplayModeModifier: ViewModifier {
    let context: IOSToolEntryContext

    func body(content: Content) -> some View {
        if context == .tabRoot {
            content.toolbarTitleDisplayMode(.inlineLarge)
        } else {
            content.navigationBarTitleDisplayMode(.inline)
        }
    }
}

extension View {
    func iosToolTitleDisplayMode(_ context: IOSToolEntryContext) -> some View {
        modifier(IOSToolTitleDisplayModeModifier(context: context))
    }
}

private struct IOSToolEntryContextKey: EnvironmentKey {
    static let defaultValue: IOSToolEntryContext = .pushed
}

extension EnvironmentValues {
    var iosToolEntryContext: IOSToolEntryContext {
        get { self[IOSToolEntryContextKey.self] }
        set { self[IOSToolEntryContextKey.self] = newValue }
    }
}

private struct IOSToolDropDelegate: DropDelegate {
    let targetID: String
    @Binding var draggedToolID: String?
    @Binding var isReordering: Bool
    let move: (String, String) -> Void

    func dropEntered(info _: DropInfo) {
        guard isReordering,
              let draggedToolID,
              draggedToolID != targetID else {
            return
        }

        move(draggedToolID, targetID)
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        guard isReordering else { return nil }
        return DropProposal(operation: .move)
    }

    func performDrop(info _: DropInfo) -> Bool {
        draggedToolID = nil
        return isReordering
    }

    func dropExited(info _: DropInfo) {}
}

extension View {
    func iosToolNavigationChrome(
        _ theme: IOSThemeTokens,
        showsBackButton: Bool = false,
        backAction: (() -> Void)? = nil
    ) -> some View {
        modifier(IOSToolNavigationChromeModifier(
            theme: theme,
            showsBackButton: showsBackButton,
            backAction: backAction
        ))
    }

    func iosToolToolbarIcon(_ theme: IOSThemeTokens) -> some View {
        self
            .font(.system(size: 13, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(theme.textSecondary)
            .frame(width: 32, height: 32)
            .contentShape(Circle())
    }
}

private struct IOSToolNavigationChromeModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    let theme: IOSThemeTokens
    let showsBackButton: Bool
    let backAction: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(showsBackButton)
            .background {
                if showsBackButton {
                    IOSNavigationPopGestureEnabler()
                        .frame(width: 0, height: 0)
                }
            }
            .toolbar {
                if showsBackButton {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            if let backAction {
                                backAction()
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
                }
            }
    }
}

struct IOSNavigationPopGestureEnabler: UIViewControllerRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.popGestureDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.popGestureDelegate = context.coordinator
        uiViewController.enablePopGesture()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let navigationController = gestureRecognizer.view?.nearestViewController()?.navigationController else {
                return true
            }
            return navigationController.viewControllers.count > 1
        }
    }

    final class Controller: UIViewController {
        var popGestureDelegate: UIGestureRecognizerDelegate?

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            enablePopGesture()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            enablePopGesture()
        }

        func enablePopGesture() {
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let navigationController = self.nearestNavigationController(),
                      let gesture = navigationController.interactivePopGestureRecognizer else {
                    return
                }
                gesture.isEnabled = navigationController.viewControllers.count > 1
                gesture.delegate = self.popGestureDelegate
            }
        }

        private func nearestNavigationController() -> UINavigationController? {
            if let navigationController {
                return navigationController
            }

            var current = parent
            while let controller = current {
                if let navigationController = controller as? UINavigationController {
                    return navigationController
                }
                if let navigationController = controller.navigationController {
                    return navigationController
                }
                current = controller.parent
            }

            return view.window?.rootViewController?.activeNavigationController()
        }
    }
}

private extension UIViewController {
    func activeNavigationController() -> UINavigationController? {
        if let presentedViewController,
           let navigationController = presentedViewController.activeNavigationController() {
            return navigationController
        }

        if let tabBarController = self as? UITabBarController {
            return tabBarController.selectedViewController?.activeNavigationController()
        }

        if let navigationController = self as? UINavigationController {
            return navigationController
        }

        if let navigationController {
            return navigationController
        }

        for child in children {
            if let navigationController = child.activeNavigationController() {
                return navigationController
            }
        }

        return nil
    }
}

private extension UIView {
    func nearestViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let viewController = current as? UIViewController {
                return viewController
            }
            responder = current.next
        }
        return nil
    }
}

struct IOSAPIRecordsListView: View {
    let records: [IOSAPIRecord]
    let openRecord: (IOSAPIRecord) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.themeTokens) private var theme

    var body: some View {
        Group {
            if records.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No API Records yet",
                        systemImage: "tray",
                        description: Text("Saved Fetch/XHR requests will appear here.")
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 48, leading: 20, bottom: 48, trailing: 20))
                }
            } else {
                ForEach(records) { record in
                    Button {
                        openRecord(record)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.title)
                                .foregroundStyle(theme.textPrimary)
                            Text(record.url)
                                .font(.caption)
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(1)
                            HStack(spacing: 8) {
                                Text(record.method)
                                Text(record.requestType)
                                if let provider = record.provider {
                                    Text(provider)
                                }
                            }
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(theme.brandPrimary)
                        }
                    }
                    .swipeActions {
                        Button {
                            record.isFavorite.toggle()
                            record.lastOpenedAt = .now
                        } label: {
                            Label(record.isFavorite ? "Unfavorite" : "Favorite", systemImage: record.isFavorite ? "star.slash" : "star")
                        }
                        .tint(.yellow)

                        Button(role: .destructive) {
                            modelContext.delete(record)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
}
