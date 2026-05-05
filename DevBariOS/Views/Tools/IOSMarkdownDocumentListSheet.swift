import SwiftData
import SwiftUI
import UIKit

struct IOSMarkdownDocumentListSheet: View {
    @Environment(\.themeTokens) private var theme
    @Environment(\.modelContext) private var modelContext

    let documents: [IOSMarkdownDocument]
    let onSelect: (IOSMarkdownDocument) -> Void
    let onCreate: () -> Void

    @State private var isSearching = false
    @State private var searchText = ""

    private var visibleDocuments: [IOSMarkdownDocument] {
        if searchText.isEmpty { return documents }
        return documents.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.content.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if isSearching {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(theme.textSecondary)
                        TextField("ios_tools_md_search", text: $searchText)
                            .textInputAutocapitalization(.never)
                    }
                    .padding(10)
                    .background(theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }

                if visibleDocuments.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: searchText.isEmpty ? "doc.richtext" : "magnifyingglass")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(theme.textSecondary.opacity(0.5))
                        Text(searchText.isEmpty ? "ios_tools_md_empty_title" : "ios_tools_md_search_empty")
                            .font(.subheadline)
                            .foregroundStyle(theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(visibleDocuments) { doc in
                        Button {
                            onSelect(doc)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(doc.title.isEmpty ? String(localized: "ios_tools_md_untitled") : doc.title)
                                        .font(.headline)
                                        .foregroundStyle(theme.textPrimary)
                                        .lineLimit(1)

                                    Text(formatDate(doc.updatedAt))
                                        .font(.caption2)
                                        .foregroundStyle(theme.textSecondary)
                                }

                                Spacer()
                            }
                            .padding(12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(theme.borderSubtle, lineWidth: 1)
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                modelContext.delete(doc)
                            } label: {
                                Label("ios_tools_md_delete", systemImage: "trash")
                            }

                            Button {
                                exportDocument(doc)
                            } label: {
                                Label("ios_tools_md_export_title", systemImage: "square.and.arrow.up")
                            }
                            .tint(.blue)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationTitle("ios_tools_md_docs_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation { isSearching.toggle(); searchText = "" }
                    } label: {
                        Image(systemName: isSearching ? "xmark.circle.fill" : "magnifyingglass")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }

    private func exportDocument(_ doc: IOSMarkdownDocument) {
        let name = (doc.title.isEmpty ? "untitled" : doc.title) + ".md"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? doc.content.write(to: tempURL, atomically: true, encoding: .utf8)

        let controller = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            var top = root
            while let presented = top.presentedViewController { top = presented }
            if let sheet = top.presentedViewController { top = sheet }
            top.present(controller, animated: true)
        }
    }
}
