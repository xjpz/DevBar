import DevBarCore
import SwiftUI

struct IOSMessageCenterView: View {
    @EnvironmentObject private var accountViewModel: IOSAccountViewModel
    @Environment(\.themeTokens) private var theme
    @State private var filter: DevBarMessageFilter = .all

    var body: some View {
        List {
            if accountViewModel.messages.isEmpty {
                emptyState
            } else {
                ForEach(accountViewModel.messages) { message in
                    NavigationLink {
                        IOSMessageDetailView(message: message)
                    } label: {
                        messageRow(message)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            Task { await accountViewModel.setRead(message, isRead: !message.isRead) }
                        } label: {
                            Label(message.isRead ? "未读" : "已读", systemImage: message.isRead ? "envelope.badge" : "envelope.open")
                        }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await accountViewModel.delete(message) }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .iosGeekScreenBackground(theme)
        .navigationTitle("消息")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            messageFilterControl
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 4)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task { await accountViewModel.markAllRead() }
                    } label: {
                        Label("全部标为已读", systemImage: "envelope.open")
                    }
                    .disabled(accountViewModel.unreadCount == 0)
                } label: {
                    Image(systemName: "ellipsis")
                        .iosToolToolbarIcon(theme)
                }
                .accessibilityLabel("更多消息操作")
            }
        }
        .task(id: filter) { await accountViewModel.refreshMessages(filter: filter) }
        .refreshable { await accountViewModel.refreshMessages(filter: filter) }
    }

    @ViewBuilder
    private var emptyState: some View {
        if accountViewModel.deviceLinkState != .linked {
            ContentUnavailableView {
                Label("当前设备尚未关联账号", systemImage: "iphone.and.arrow.forward")
            } description: {
                Text(accountViewModel.deviceLinkMessage ?? "关联成功后即可查询这台 iPhone 的 Push 消息")
            } actions: {
                Button("重新关联") {
                    Task { await accountViewModel.retryDeviceLink() }
                }
                .disabled(accountViewModel.deviceLinkState == .linking)
            }
            .listRowBackground(Color.clear)
        } else {
            ContentUnavailableView(
                filter == .unread ? "没有未读消息" : "暂无消息",
                systemImage: "tray",
                description: Text("新消息会显示在这里")
            )
            .listRowBackground(Color.clear)
        }
    }

    private var messageFilterControl: some View {
        HStack(spacing: 8) {
            messageFilterButton(.all, title: "全部", accessibilityLabel: "显示全部消息")
            messageFilterButton(.unread, title: "未读", accessibilityLabel: "只显示未读消息")
        }
        .frame(height: 44)
        .animation(.easeInOut(duration: 0.18), value: filter)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("消息筛选")
    }

    private func messageFilterButton(
        _ option: DevBarMessageFilter,
        title: String,
        accessibilityLabel: String
    ) -> some View {
        let isSelected = filter == option

        return Button {
            guard !isSelected else { return }
            filter = option
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? theme.brandPrimary : theme.textSecondary)
                .padding(.horizontal, 16)
                .frame(minWidth: 72, minHeight: 44)
                .background {
                    Capsule()
                        .fill(
                            isSelected
                                ? theme.surfacePrimary.opacity(theme.isGeek ? 0.92 : 1)
                                : theme.surfaceSecondary.opacity(theme.isGeek ? 0.72 : 0.92)
                        )
                        .padding(.vertical, 4)
                        .shadow(
                            color: isSelected
                                ? theme.textPrimary.opacity(theme.isGeek ? 0.18 : 0.08)
                                : .clear,
                            radius: 2,
                            y: 1
                        )
                }
                .overlay {
                    Capsule()
                        .stroke(
                            isSelected
                                ? theme.brandPrimary.opacity(0.42)
                                : theme.borderSubtle.opacity(0.72),
                            lineWidth: 1
                        )
                        .padding(.vertical, 4)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isSelected ? "已选择" : "未选择")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func messageRow(_ message: DevBarMessage) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                if !message.isRead {
                    Circle()
                        .fill(theme.brandPrimary)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                }
                Text(message.title)
                    .font(.body.weight(message.isRead ? .regular : .semibold))
                    .lineLimit(2)
            }
            if let preview = message.preview { Text(preview).font(.subheadline).foregroundStyle(theme.textSecondary).lineLimit(2) }
            Text(Date(timeIntervalSince1970: TimeInterval(message.createdAt) / 1_000), style: .relative)
                .font(.caption2).foregroundStyle(theme.textSecondary)
        }
        .padding(.vertical, 4)
    }
}

struct IOSMessageDetailView: View {
    @EnvironmentObject private var accountViewModel: IOSAccountViewModel
    let message: DevBarMessage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(message.title).font(.title2.bold())
                Text(Date(timeIntervalSince1970: TimeInterval(message.createdAt) / 1_000).formatted(date: .long, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                Text(message.body ?? message.preview ?? "")
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let rawURL = message.targetURL,
                   let url = PushNotificationURLPolicy.validatedURL(from: rawURL) {
                    Link(destination: url) {
                        Label("打开链接", systemImage: "arrow.up.right.square")
                    }
                }
            }
            .padding()
        }
        .navigationTitle("消息详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task {
            if !message.isRead { await accountViewModel.setRead(message, isRead: true) }
        }
    }
}
