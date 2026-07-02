import SwiftData
import SwiftUI
import UIKit

// MARK: - Main View

struct IOSMarkdownView: View {
    @Environment(\.themeTokens) private var theme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \IOSMarkdownDocument.updatedAt, order: .reverse) private var documents: [IOSMarkdownDocument]

    @State private var currentDocument: IOSMarkdownDocument = IOSMarkdownDocument()
    @State private var showDocumentList = false
    @State private var isEditing = true
    @State private var isScrolledDown = false
    @State private var previewScrollToTop = false
    @State private var previewPullTriggered = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    Button { isEditing = true } label: {
                        Text("ios_tools_md_edit")
                            .font(.headline.weight(isEditing ? .semibold : .regular))
                            .foregroundStyle(isEditing ? theme.brandPrimary : theme.textSecondary)
                    }
                    Button { isEditing = false } label: {
                        Text("ios_tools_md_preview")
                            .font(.headline.weight(!isEditing ? .semibold : .regular))
                            .foregroundStyle(!isEditing ? theme.brandPrimary : theme.textSecondary)
                    }
                }
                .padding(.vertical, 10)

                if isEditing {
                    IOSMarkdownTextView(
                        text: Binding(
                            get: { currentDocument.content },
                            set: { newValue in
                                currentDocument.content = newValue
                                currentDocument.title = extractTitle(from: newValue)
                                currentDocument.updatedAt = Date()
                            }
                        ),
                        onScroll: { scrolledDown in
                            isScrolledDown = scrolledDown
                        },
                        onPullToBrowse: {
                            showDocumentList = true
                        }
                    )
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                Color.clear.frame(height: 0).id("previewTop")

                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: PreviewScrollOffsetKey.self,
                                        value: geo.frame(in: .named("previewScroll")).minY
                                    )
                                }
                                .frame(height: 0)

                                ForEach(parseBlocks(from: currentDocument.content), id: \.id) { block in
                                    renderBlock(block)
                                }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .coordinateSpace(name: "previewScroll")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onPreferenceChange(PreviewScrollOffsetKey.self) { offset in
                            isScrolledDown = offset < -300
                            if offset > 80 && !previewPullTriggered {
                                previewPullTriggered = true
                                showDocumentList = true
                            }
                            if offset <= 0 {
                                previewPullTriggered = false
                            }
                        }
                        .onChange(of: previewScrollToTop) { _, flag in
                            if flag {
                                withAnimation { proxy.scrollTo("previewTop", anchor: .top) }
                                previewScrollToTop = false
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isScrolledDown {
                Button {
                    if isEditing {
                        NotificationCenter.default.post(name: .markdownScrollToTop, object: nil)
                    } else {
                        previewScrollToTop = true
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(theme.brandPrimary)
                        .background(Circle().fill(theme.surfacePrimary).shadow(color: .black.opacity(0.15), radius: 4, y: 2))
                }
                .padding(.trailing, 16)
                .padding(.bottom, 16)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isScrolledDown)
        .background(Color.clear)
            .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle(currentDocument.title.isEmpty ? String(localized: "ios_tools_md_untitled") : currentDocument.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .iosToolNavigationChrome(theme, showsBackButton: true)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { createNewDocument() } label: {
                    Image(systemName: "plus")
                        .iosToolToolbarIcon(theme)
                }
            }
        }
        .sheet(isPresented: $showDocumentList) {
            IOSMarkdownDocumentListSheet(
                documents: documents,
                onSelect: { doc in
                    currentDocument = doc
                    showDocumentList = false
                },
                onCreate: {
                    let doc = IOSMarkdownDocument()
                    modelContext.insert(doc)
                    currentDocument = doc
                    showDocumentList = false
                }
            )
        }
        .onAppear { loadInitialDocument() }
        .onChange(of: documents) { _, newDocs in
            handleDeletedDocument(newDocs)
        }
    }

    // MARK: - Document management

    private func loadInitialDocument() {
        if let first = documents.first {
            currentDocument = first
        } else {
            modelContext.insert(currentDocument)
        }
    }

    private func createNewDocument() {
        let doc = IOSMarkdownDocument()
        modelContext.insert(doc)
        currentDocument = doc
        isEditing = true
    }

    private func handleDeletedDocument(_ newDocs: [IOSMarkdownDocument]) {
        if !newDocs.contains(where: { $0.id == currentDocument.id }) {
            if let first = newDocs.first {
                currentDocument = first
            } else {
                let doc = IOSMarkdownDocument()
                modelContext.insert(doc)
                currentDocument = doc
            }
        }
    }

    // MARK: - Title extraction

    private func extractTitle(from content: String) -> String {
        guard let firstLine = content.components(separatedBy: "\n").first else { return "" }
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") {
            return String(trimmed.drop(while: { $0 == "#" || $0 == " " }))
        }
        return ""
    }

    // MARK: - Block rendering

    @ViewBuilder
    private func renderBlock(_ block: MDBlock) -> some View {
        switch block.type {
        case .heading:
            let level = block.headingLevel
            Text(renderInline(block.content))
                .font(level == 1 ? .largeTitle.weight(.bold) :
                        level == 2 ? .title.weight(.semibold) :
                        level == 3 ? .title3.weight(.semibold) :
                        .headline)
                .foregroundStyle(theme.textPrimary)
        case .paragraph:
            Text(renderInline(block.content))
                .font(.body)
                .foregroundStyle(theme.textPrimary)
        case .listItem:
            HStack(alignment: .top, spacing: 8) {
                Text("\u{2022}")
                    .foregroundStyle(theme.brandPrimary)
                Text(renderInline(block.content))
                    .font(.body)
                    .foregroundStyle(theme.textPrimary)
            }
        case .blockquote:
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.brandPrimary.opacity(0.5))
                    .frame(width: 4)
                    .padding(.trailing, 12)
                Text(renderInline(block.content))
                    .font(.body.italic())
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(12)
            .background(theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .codeBlock:
            Text(block.content)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func renderInline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    // MARK: - Block parser

    private func parseBlocks(from source: String) -> [MDBlock] {
        var blocks: [MDBlock] = []
        let lines = source.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                i += 1
                blocks.append(MDBlock(type: .codeBlock, content: codeLines.joined(separator: "\n")))
                continue
            }

            if let level = headingLevel(trimmed) {
                let content = String(trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces))
                blocks.append(MDBlock(type: .heading, content: content, headingLevel: level))
                i += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                let content = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                blocks.append(MDBlock(type: .blockquote, content: content))
                i += 1
                continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let content = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                blocks.append(MDBlock(type: .listItem, content: content))
                i += 1
                continue
            }

            if !trimmed.isEmpty {
                blocks.append(MDBlock(type: .paragraph, content: trimmed))
            }
            i += 1
        }

        return blocks
    }

    private func headingLevel(_ line: String) -> Int? {
        var count = 0
        for char in line {
            if char == "#" { count += 1 } else { break }
        }
        return (1...6).contains(count) ? count : nil
    }
}

// MARK: - Custom UITextView Wrapper

extension Notification.Name {
    static let markdownScrollToTop = Notification.Name("markdownScrollToTop")
}

struct IOSMarkdownTextView: UIViewRepresentable {
    @Binding var text: String
    let onScroll: (Bool) -> Void
    let onPullToBrowse: () -> Void

    private let pullThreshold: CGFloat = -80

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = .monospacedSystemFont(ofSize: UIFont.systemFontSize, weight: .regular)
        tv.textColor = .label
        tv.backgroundColor = .clear
        tv.keyboardDismissMode = .onDrag
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        tv.isEditable = true
        tv.isSelectable = true
        tv.isScrollEnabled = true
        tv.bounces = true
        tv.alwaysBounceVertical = true
        tv.text = text
        context.coordinator.textView = tv

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleScrollToTop),
            name: .markdownScrollToTop,
            object: nil
        )

        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text {
            tv.text = text
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIScrollViewDelegate {
        var parent: IOSMarkdownTextView
        weak var textView: UITextView?
        private var hasTriggeredPull = false

        init(_ parent: IOSMarkdownTextView) {
            self.parent = parent
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func textViewDidChange(_ tv: UITextView) {
            parent.text = tv.text
        }

        func scrollViewDidScroll(_ sv: UIScrollView) {
            let offsetY = sv.contentOffset.y
            let threshold: CGFloat = 300
            parent.onScroll(offsetY > threshold)

            if offsetY < parent.pullThreshold && !hasTriggeredPull {
                hasTriggeredPull = true
                parent.onPullToBrowse()
            }

            if offsetY >= 0 {
                hasTriggeredPull = false
            }
        }

        @objc func handleScrollToTop() {
            textView?.setContentOffset(.zero, animated: true)
        }
    }
}

// MARK: - Block Model

private struct PreviewScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct MDBlock: Identifiable {
    let id = UUID()
    let type: BlockType
    var content: String
    var headingLevel: Int = 0

    enum BlockType {
        case heading, paragraph, listItem, blockquote, codeBlock
    }
}
