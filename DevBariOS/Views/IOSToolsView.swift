import DevBarCore
import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

struct IOSToolsView: View {
    @EnvironmentObject private var appViewModel: IOSAppViewModel
    @Environment(\.themeTokens) private var theme
    @State private var toolOrder = IOSToolOrderStore().load()
    @State private var draggedToolID: String?
    @State private var isReordering = false

    private let orderStore = IOSToolOrderStore()

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(orderedTools) { tool in
                    toolGridItem(tool)
                }
            }
            .padding(16)
        }
        .iosGeekScreenBackground(theme)
        .navigationTitle("ios_tab_tools")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if isReordering {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            isReordering = false
                            draggedToolID = nil
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("ios.tools.screen")
    }

    private var orderedTools: [IOSToolDefinition] {
        let tools = availableTools
        let toolByID = Dictionary(uniqueKeysWithValues: tools.map { ($0.id, $0) })
        let orderedIDs = IOSToolOrder.resolvedOrder(
            savedOrder: toolOrder,
            defaultOrder: tools.map(\.id)
        )

        return orderedIDs.compactMap { toolByID[$0] }
    }

    private var availableTools: [IOSToolDefinition] {
        var tools: [IOSToolDefinition] = [
            IOSToolDefinition(id: "api-client", title: "API 调试", subtitle: "API Client", systemImage: "globe", iconColor: .cyan),
            IOSToolDefinition(id: "formatter", title: "格式化", subtitle: "Formatter", systemImage: "curlybraces", iconColor: .yellow),
            IOSToolDefinition(id: "base64", title: "Base64", subtitle: "编码 / 解码", systemImage: "lock.square", iconColor: .indigo),
            IOSToolDefinition(id: "timestamp", title: "时间戳", subtitle: "Timestamp", systemImage: "clock", iconColor: .mint),
            IOSToolDefinition(id: "markdown", title: "Markdown", subtitle: "编辑 / 预览", systemImage: "doc.richtext", iconColor: .orange),
            IOSToolDefinition(id: "qr-code", title: "二维码", subtitle: "QR Code", systemImage: "qrcode", iconColor: .blue),
            IOSToolDefinition(id: "mac-relay", title: "Mac 中继", subtitle: "Relay", systemImage: "macbook.and.iphone", iconColor: .green),
            IOSToolDefinition(id: "terminal", title: "终端", subtitle: "Terminal", systemImage: "terminal.fill", iconColor: .green),
        ]

        if #available(iOS 18.0, *) {
            tools.append(IOSToolDefinition(id: "translation", title: "翻译", subtitle: "Translate", systemImage: "character.book.closed", iconColor: .teal))
        }

        tools.append(contentsOf: [
            IOSToolDefinition(id: "ocr", title: "文字识别", subtitle: "OCR", systemImage: "doc.text.viewfinder", iconColor: .purple),
            IOSToolDefinition(id: "speech-to-text", title: "语音转文字", subtitle: "Speech to Text", systemImage: "mic.fill", iconColor: .pink),
            IOSToolDefinition(id: "memo", title: "备忘录", subtitle: "Memo", systemImage: "note.text", iconColor: .brown),
        ])

        tools.append(contentsOf: appViewModel.toolsChatProviders.map { provider in
            IOSToolDefinition(
                id: "chatbot-\(provider.rawValue)",
                title: provider.toolTitle,
                subtitle: provider.toolSubtitle,
                systemImage: "bubble.left.and.bubble.right.fill",
                iconColor: .green
            )
        })

        return tools
    }

    @ViewBuilder
    private func toolGridItem(_ tool: IOSToolDefinition) -> some View {
        Group {
            if isReordering {
                toolCard(tool)
            } else {
                NavigationLink {
                    destination(for: tool.id)
                } label: {
                    toolCard(tool)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(draggedToolID == tool.id ? 0.96 : 1)
        .opacity(draggedToolID == tool.id ? 0.72 : 1)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35)
                .onEnded { _ in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        isReordering = true
                    }
                }
        )
        .onDrag {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                isReordering = true
                draggedToolID = tool.id
            }
            return NSItemProvider(object: tool.id as NSString)
        }
        .onDrop(
            of: [UTType.plainText],
            delegate: IOSToolDropDelegate(
                targetID: tool.id,
                draggedToolID: $draggedToolID,
                isReordering: $isReordering,
                move: moveTool
            )
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: orderedTools.map(\.id))
    }

    private func toolCard(_ tool: IOSToolDefinition) -> some View {
        IOSToolCard(
            title: tool.title,
            subtitle: tool.subtitle,
            systemImage: tool.systemImage,
            iconColor: tool.iconColor,
            theme: theme,
            isReordering: isReordering
        )
    }

    @ViewBuilder
    private func destination(for id: String) -> some View {
        if let provider = chatProvider(from: id) {
            IOSHermesConversationListView(provider: provider)
        } else {
            switch id {
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
            case "translation":
                if #available(iOS 18.0, *) {
                    IOSTranslationView()
                }
            case "ocr":
                IOSOCRView()
            case "speech-to-text":
                IOSSpeechToTextView()
            case "memo":
                IOSMemoListView()
            default:
                EmptyView()
            }
        }
    }

    private func chatProvider(from id: String) -> ChatBotProviderKind? {
        guard id.hasPrefix("chatbot-") else { return nil }
        let rawValue = String(id.dropFirst("chatbot-".count))
        return ChatBotProviderKind(rawValue: rawValue)
    }

    private func moveTool(_ sourceID: String, _ targetID: String) {
        let currentOrder = orderedTools.map(\.id)
        let updatedOrder = IOSToolOrder.moving(sourceID, before: targetID, in: currentOrder)

        guard updatedOrder != currentOrder else { return }

        toolOrder = updatedOrder
        orderStore.save(updatedOrder)
    }
}

struct IOSToolCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let iconColor: Color
    let theme: IOSThemeTokens
    var isReordering = false

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

private struct IOSToolDefinition: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let iconColor: Color
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

private struct IOSNavigationPopGestureEnabler: UIViewControllerRepresentable {
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
