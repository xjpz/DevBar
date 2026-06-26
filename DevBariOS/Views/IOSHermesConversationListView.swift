import SwiftData
import SwiftUI

struct IOSHermesConversationListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.themeTokens) private var theme
    @Query(
        filter: #Predicate<IOSHermesConversation> { !$0.isArchived },
        sort: \IOSHermesConversation.updatedAt,
        order: .reverse
    )
    private var conversations: [IOSHermesConversation]

    @State private var isNewChatPresented = false

    var body: some View {
        List {
            if conversations.isEmpty {
                emptyState
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 48, leading: 18, bottom: 0, trailing: 18))
            } else {
                ForEach(conversations) { conversation in
                    NavigationLink {
                        IOSHermesChatView(conversation: conversation)
                    } label: {
                        conversationRow(conversation)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            archive(conversation)
                        } label: {
                            Label("ios_common_delete", systemImage: "trash")
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .iosGeekScreenBackground(theme)
        .navigationTitle("ios_hermes_title")
        .toolbarTitleDisplayMode(.inlineLarge)
        .iosToolNavigationChrome(theme)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isNewChatPresented = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityIdentifier("ios.hermes.conversation.new")
            }
        }
        .navigationDestination(isPresented: $isNewChatPresented) {
            IOSHermesChatView()
        }
        .accessibilityIdentifier("ios.hermes.conversation.list")
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 40)
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(theme.textSecondary.opacity(0.58))
            VStack(spacing: 6) {
                Text("ios_hermes_empty_title")
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                Text("Hermes Chat history is saved on this iPhone.")
                    .font(theme.footnoteFont)
                    .foregroundStyle(theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            Button {
                isNewChatPresented = true
            } label: {
                Label("New Chat", systemImage: "plus")
                    .font(theme.bodyFont.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(theme.brandPrimary.opacity(theme.isGeek ? 0.22 : 0.14), in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.brandPrimary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    private func conversationRow(_ conversation: IOSHermesConversation) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(theme.brandPrimary.opacity(theme.isGeek ? 0.18 : 0.12))
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.brandPrimary)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(conversation.displayTitle)
                        .font(theme.bodyFont.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    if conversation.messageCount > 0 {
                        Text("\(conversation.messageCount)")
                            .font(theme.captionFont.weight(.semibold))
                            .foregroundStyle(theme.textTertiary)
                    }
                    Spacer(minLength: 0)
                    Text(Self.relativeFormatter.localizedString(for: conversation.updatedAt, relativeTo: Date()))
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textTertiary)
                }

                Text(conversation.lastMessagePreview.isEmpty ? "New conversation" : conversation.lastMessagePreview)
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

    private func archive(_ conversation: IOSHermesConversation) {
        conversation.isArchived = true
        conversation.archivedAt = Date()
        conversation.updatedAt = Date()
        try? modelContext.save()
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
