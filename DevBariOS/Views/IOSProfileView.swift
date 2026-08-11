import AuthenticationServices
import CryptoKit
import DevBarCore
import Security
import SwiftUI

struct IOSProfileEntryAvatar: View {
    let avatarData: Data?
    let unreadCount: Int

    private let size: CGFloat = 24

    var body: some View {
        profileImage
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(alignment: .topTrailing) {
                if unreadCount > 0 {
                    Circle()
                        .fill(.red)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(.background, lineWidth: 1.5))
                        .offset(x: 3, y: -3)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .accessibilityLabel(unreadCount > 0 ? "个人中心，\(unreadCount) 条未读消息" : "个人中心")
    }

    @ViewBuilder
    private var profileImage: some View {
        if let avatarData, let image = UIImage(data: avatarData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Image("AppIconPreviewSmileBlueBorder")
                .resizable()
                .scaledToFill()
        }
    }
}

struct IOSProfileView: View {
    @EnvironmentObject private var appViewModel: IOSAppViewModel
    @EnvironmentObject private var accountViewModel: IOSAccountViewModel
    @Environment(\.themeTokens) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var rawNonce: String?

    var body: some View {
        ZStack {
            IOSProfileBackground()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                profileNavigationHeader

                GeometryReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            profileHeader

                            if accountViewModel.isAuthenticated {
                                messageCard
                                accountAndPrivacyCard
                                Spacer(minLength: 18)
                                logoutCard
                            } else {
                                signInCard
                            }
                        }
                        .frame(width: contentWidth(for: proxy.size.width), alignment: .leading)
                        .frame(minHeight: max(proxy.size.height - 12, 0), alignment: .top)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                        .frame(width: proxy.size.width)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scrollIndicators(.hidden)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .background {
            IOSNavigationPopGestureEnabler()
                .frame(width: 0, height: 0)
        }
        .alert("操作失败", isPresented: Binding(
            get: { accountViewModel.errorMessage != nil },
            set: { if !$0 { accountViewModel.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(accountViewModel.errorMessage ?? "")
        }
    }

    private var profileNavigationHeader: some View {
        ZStack {
            Text("个人中心")
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(profilePrimaryText)

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(profilePrimaryText)
                        .frame(width: 40, height: 40)
                        .background {
                            Circle()
                                .fill(isDarkAppearance ? Color.white.opacity(0.08) : Color.white.opacity(0.38))
                                .overlay {
                                    Circle().stroke(
                                        isDarkAppearance ? Color.white.opacity(0.12) : Color(hex: "AFC4E3").opacity(0.46),
                                        lineWidth: 1
                                    )
                                }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回")

                Spacer()
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
    }

    private var profileHeader: some View {
        HStack(spacing: 16) {
            profileAvatar(size: 76)

            VStack(alignment: .leading, spacing: 6) {
                Text(accountViewModel.profile?.displayName ?? "DevBar 用户")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(profilePrimaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    Image(systemName: accountViewModel.isAuthenticated ? "apple.logo" : "person.crop.circle.badge.plus")
                        .font(.system(size: 14, weight: .semibold))
                    Text(accountViewModel.isAuthenticated ? "已通过 Apple 登录" : "登录后同步昵称和消息")
                        .font(.system(size: 14))
                }
                .foregroundStyle(profileSecondaryText)

                if accountViewModel.isAuthenticated,
                   let message = accountViewModel.deviceLinkMessage,
                   accountViewModel.deviceLinkState != .linked {
                    Button {
                        Task { await accountViewModel.retryDeviceLink() }
                    } label: {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(accountViewModel.deviceLinkState == .conflict ? .red : profileSecondaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                    .disabled(accountViewModel.deviceLinkState == .linking)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private var messageCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                NavigationLink {
                    IOSMessageCenterView()
                } label: {
                    HStack(spacing: 6) {
                        IOSProfileGlowIcon(
                            systemName: "ellipsis.message.fill",
                            colors: [Color(hex: "36DDF4"), Color(hex: "4D8DFF")],
                            size: 27
                        )

                        Text("消息")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(profilePrimaryText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("消息，进入消息页面")

                Spacer()

                NavigationLink {
                    IOSMessageCenterView()
                } label: {
                    Text("\(accountViewModel.unreadCount)条未读")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(hex: "45B8FF"))
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background {
                            Capsule()
                                .fill(Color(hex: "172943").opacity(isDarkAppearance ? 0.88 : 0.08))
                                .overlay {
                                    Capsule().stroke(Color(hex: "6FA9EB").opacity(isDarkAppearance ? 0.17 : 0.22), lineWidth: 1)
                                }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(accountViewModel.unreadCount)条未读，进入消息页面")
            }
            .padding(.bottom, 9)

            Rectangle()
                .fill(profileTertiaryText.opacity(isDarkAppearance ? 0.18 : 0.14))
                .frame(height: 0.5)
                .padding(.horizontal, 10)
                .accessibilityHidden(true)

            if accountViewModel.messages.isEmpty {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("暂无消息")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(profilePrimaryText)
                        Text("新消息会显示在这里")
                            .font(.system(size: 12))
                            .foregroundStyle(profileSecondaryText)
                    }
                    Spacer()
                }
                .padding(.horizontal, 11)
                .frame(height: 62)
            } else if let message = accountViewModel.messages.first {
                NavigationLink {
                    IOSMessageDetailView(message: message)
                } label: {
                    IOSProfileMessageRow(message: message)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .profileGlassCard(isDark: isDarkAppearance, cornerRadius: 20)
    }

    private var accountAndPrivacyCard: some View {
        NavigationLink {
            IOSAccountPrivacyView()
        } label: {
            HStack(spacing: 10) {
                IOSProfileShieldIcon(size: 31)

                VStack(alignment: .leading, spacing: 1) {
                    Text("账户与隐私")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(profilePrimaryText)
                    Text("管理你的账户安全与隐私设置")
                        .font(.system(size: 11))
                        .foregroundStyle(profileSecondaryText)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(profileTertiaryText)
            }
            .padding(.horizontal, 14)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .profileGlassCard(isDark: isDarkAppearance, cornerRadius: 18)
    }

    private var logoutCard: some View {
        Button(role: .destructive) {
            Task { await accountViewModel.logout() }
        } label: {
            HStack(spacing: 8) {
                Spacer()
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 16, weight: .semibold))
                Text(accountViewModel.isWorking ? "正在退出…" : "退出登录")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Spacer()
            }
            .foregroundStyle(Color(hex: "FF5D82"))
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: isDarkAppearance
                                ? [Color(hex: "18243B").opacity(0.86), Color(hex: "511C36").opacity(0.80)]
                                : [Color.white.opacity(0.66), Color(hex: "FFE7EF").opacity(0.72)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay {
                        Capsule().stroke(
                            LinearGradient(
                                colors: isDarkAppearance
                                    ? [Color(hex: "526A99").opacity(0.34), Color(hex: "FF4F7B").opacity(0.68)]
                                    : [Color(hex: "AFC4E8").opacity(0.42), Color(hex: "FF7FA2").opacity(0.56)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1
                        )
                    }
                    .shadow(color: Color(hex: "B64A72").opacity(isDarkAppearance ? 0.08 : 0.06), radius: 16, y: 6)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(accountViewModel.isWorking)
        .frame(maxWidth: .infinity)
    }

    private var signInCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("登录 DevBar")
                    .font(.title3.bold())
                    .foregroundStyle(profilePrimaryText)
                Text("使用 Apple 登录后，可以同步昵称并查看消息。")
                    .font(.subheadline)
                    .foregroundStyle(profileSecondaryText)
            }

            SignInWithAppleButton(.signIn) { request in
                let nonce = IOSAppleNonce.make()
                rawNonce = nonce
                request.requestedScopes = [.fullName, .email]
                request.nonce = IOSAppleNonce.sha256(nonce)
            } onCompletion: { result in
                handleAppleCompletion(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .disabled(accountViewModel.isWorking)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .profileGlassCard(isDark: isDarkAppearance, cornerRadius: 24)
    }

    private var profilePrimaryText: Color {
        isDarkAppearance ? Color.white.opacity(0.96) : theme.textPrimary
    }

    private var profileSecondaryText: Color {
        isDarkAppearance ? Color(hex: "9FB0C8") : theme.textSecondary
    }

    private var profileTertiaryText: Color {
        isDarkAppearance ? Color(hex: "7F93AD") : theme.textTertiary
    }

    private var isDarkAppearance: Bool {
        colorScheme == .dark
    }

    private func contentWidth(for viewportWidth: CGFloat) -> CGFloat {
        min(max(viewportWidth - 40, 0), 620)
    }

    @ViewBuilder
    private func profileAvatar(size: CGFloat) -> some View {
        Group {
            if let avatarData = appViewModel.macThemeWidgetAvatarData,
               let image = UIImage(data: avatarData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image("AppIconPreviewSmileBlueBorder")
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().stroke(
                LinearGradient(
                    colors: [Color(hex: "4EDAFF"), Color.white.opacity(0.92), Color(hex: "9B84FF")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 2.5
            )
        }
        .shadow(color: Color(hex: "24AFFF").opacity(isDarkAppearance ? 0.40 : 0.13), radius: 17, y: 5)
    }

    private func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        guard case .success(let authorization) = result,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8),
              let rawNonce else {
            if case .failure(let error) = result,
               (error as? ASAuthorizationError)?.code != .canceled {
                accountViewModel.errorMessage = error.localizedDescription
            }
            return
        }
        let formatter = PersonNameComponentsFormatter()
        let displayName = credential.fullName
            .map { formatter.string(from: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
        self.rawNonce = nil
        Task {
            await accountViewModel.completeAppleSignIn(
                identityToken: identityToken,
                nonce: rawNonce,
                displayNameCandidate: displayName
            )
        }
    }
}

private struct IOSProfileMessageRow: View {
    @Environment(\.themeTokens) private var theme
    @Environment(\.colorScheme) private var colorScheme
    let message: DevBarMessage

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                IOSMessageMarkdownText(source: message.title, syntax: .inline)
                    .font(.system(size: 15))
                    .fontWeight(message.isRead ? .regular : .semibold)
                    .foregroundStyle(isDarkAppearance ? Color.white.opacity(0.95) : theme.textPrimary)
                    .lineLimit(1)
                if let preview = message.preview {
                    IOSMessageMarkdownText(source: preview, syntax: .inline)
                        .font(.system(size: 12))
                        .foregroundStyle(isDarkAppearance ? Color(hex: "9FB0C8") : theme.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 2)

            HStack(spacing: 5) {
                Text(messageTime)
                    .font(.system(size: 12))
                    .foregroundStyle(isDarkAppearance ? Color(hex: "9FB0C8") : theme.textSecondary)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isDarkAppearance ? Color(hex: "7F93AD") : theme.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 66)
    }

    private var messageTime: String {
        let date = Date(timeIntervalSince1970: TimeInterval(message.createdAt) / 1_000)
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if Calendar.current.isDateInYesterday(date) {
            return "昨天"
        }
        return date.formatted(.dateTime.month().day())
    }

    private var isDarkAppearance: Bool {
        colorScheme == .dark
    }
}

private struct IOSProfileBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image("ProfileSpaceBackground")
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .overlay {
                if colorScheme == .dark {
                    Color.black.opacity(0.08)
                } else {
                    Color.white.opacity(0.02)
                }
            }
            .ignoresSafeArea()
    }
}

private struct IOSProfileGlowIcon: View {
    let systemName: String
    let colors: [Color]
    var size: CGFloat = 42

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.58, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                colors.last ?? .blue
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct IOSProfileShieldIcon: View {
    var size: CGFloat = 31

    var body: some View {
        ZStack {
            Image(systemName: "shield.fill")
                .font(.system(size: size * 0.76, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "8B7AD8"), Color(hex: "6259B8")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: "checkmark")
                .font(.system(size: size * 0.27, weight: .black))
                .foregroundStyle(Color.white)
                .offset(y: -size * 0.015)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct IOSAccountPrivacyView: View {
    @EnvironmentObject private var accountViewModel: IOSAccountViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeTokens) private var theme
    @State private var isShowingDeletionConfirmation = false

    var body: some View {
        List {
            Section("登录方式") {
                HStack(spacing: 10) {
                    Text("Apple 登录")
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(Color(hex: "19A95B"))
                            .frame(width: 20, height: 20)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .accessibilityHidden(true)
                    Text("已登录")
                        .foregroundStyle(Color(hex: "16894B"))
                }
                .frame(height: 50)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }

            if let profile = accountViewModel.profile {
                Section("账户") {
                    NavigationLink {
                        IOSDisplayNameEditorView(displayName: profile.displayName)
                    } label: {
                        LabeledContent("昵称", value: profile.displayName)
                    }
                    .frame(height: 50)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                }
            }

            Section {
                Button(role: .destructive) {
                    isShowingDeletionConfirmation = true
                } label: {
                    HStack {
                        Label("注销账户", systemImage: "person.crop.circle.badge.xmark")
                        Spacer()
                        if accountViewModel.isWorking {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .frame(height: 50)
                }
                .disabled(accountViewModel.isWorking)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            } footer: {
                Text("注销后，昵称、消息、Push Key 和设备账号关联将被永久删除，且无法恢复。")
            }
        }
        .scrollContentBackground(.hidden)
        .iosGeekScreenBackground(theme)
        .navigationTitle("账户与隐私")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .alert("确认注销账户？", isPresented: $isShowingDeletionConfirmation) {
            Button("取消", role: .cancel) {}
            Button("永久注销", role: .destructive) {
                Task {
                    if await accountViewModel.deleteAccount() {
                        dismiss()
                    }
                }
            }
        } message: {
            Text("该操作会永久删除账户及相关数据。若以后再次使用 Apple 登录，将创建一个全新账户。")
        }
        .alert("注销失败", isPresented: Binding(
            get: { accountViewModel.errorMessage != nil },
            set: { if !$0 { accountViewModel.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(accountViewModel.errorMessage ?? "")
        }
    }
}

private struct IOSDisplayNameEditorView: View {
    @EnvironmentObject private var accountViewModel: IOSAccountViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeTokens) private var theme
    @FocusState private var isDisplayNameFocused: Bool
    @State private var displayNameDraft: String

    private let originalDisplayName: String

    init(displayName: String) {
        originalDisplayName = displayName
        _displayNameDraft = State(initialValue: displayName)
    }

    var body: some View {
        List {
            Section("昵称") {
                TextField("请输入昵称", text: $displayNameDraft)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .focused($isDisplayNameFocused)
                    .onSubmit { saveDisplayName() }
            }
        }
        .scrollContentBackground(.hidden)
        .iosGeekScreenBackground(theme)
        .navigationTitle("修改昵称")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(accountViewModel.isWorking ? "保存中…" : "保存") {
                    saveDisplayName()
                }
                .disabled(!canSave || accountViewModel.isWorking)
            }
        }
        .task {
            await Task.yield()
            isDisplayNameFocused = true
        }
        .alert("保存失败", isPresented: Binding(
            get: { accountViewModel.errorMessage != nil },
            set: { if !$0 { accountViewModel.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(accountViewModel.errorMessage ?? "")
        }
    }

    private var normalizedDisplayName: String {
        displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !normalizedDisplayName.isEmpty && normalizedDisplayName != originalDisplayName
    }

    private func saveDisplayName() {
        guard canSave, !accountViewModel.isWorking else { return }
        let displayName = normalizedDisplayName
        Task {
            if await accountViewModel.updateDisplayName(displayName) {
                dismiss()
            }
        }
    }
}

private extension View {
    func profileGlassCard(isDark: Bool, cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background {
            shape
                .fill(isDark ? Color(hex: "111D31").opacity(0.78) : Color.white.opacity(0.58))
                .overlay {
                    shape.stroke(
                        isDark ? Color(hex: "6684B4").opacity(0.24) : Color(hex: "AFC4E3").opacity(0.34),
                        lineWidth: 1
                    )
                }
                .shadow(color: Color(hex: "6684A8").opacity(isDark ? 0.16 : 0.07), radius: 16, y: 6)
        }
    }

}

private enum IOSAppleNonce {
    static func make(length: Int = 32) -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String((0..<length).compactMap { _ in
            var random: UInt8 = 0
            guard SecRandomCopyBytes(kSecRandomDefault, 1, &random) == errSecSuccess else { return nil }
            return characters[Int(random) % characters.count]
        })
    }

    static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
