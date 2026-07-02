import SwiftUI
import SwiftData
import Combine
import CryptoKit

// MARK: - Memo

struct IOSMemoListView: View {
    @Environment(\.themeTokens) private var theme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \IOSMemoItem.updatedAt, order: .reverse) private var memos: [IOSMemoItem]
    @StateObject private var vault = IOSMemoVault()

    @State private var isShowingNewMemo = false
    @State private var editingMemo: IOSMemoItem?
    @State private var showPasswordSheet = false
    @State private var passwordSheetMode: IOSMemoPasswordSheet.PasswordMode = .setPassword
    @State private var showSecurityPicker = false
    @State private var showDestroyAlert = false
    @State private var tapCount = 0
    @State private var tapTimer: Timer?
    @State private var searchText = ""
    @State private var isSearching = false

    private var visibleMemos: [IOSMemoItem] {
        let isLocked = vault.isPasswordSet && !vault.isUnlocked
        var result = isLocked ? memos.filter { !$0.isEncrypted } : memos
        if !searchText.isEmpty {
            result = result.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
        return result
    }

    var body: some View {
        List {
            if isSearching {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(theme.textSecondary)
                    TextField("ios_tools_memo_search", text: $searchText)
                        .textInputAutocapitalization(.never)
                }
                .padding(10)
                .iosGlassContainer(theme, cornerRadius: 10)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }

            if visibleMemos.isEmpty {
                VStack(spacing: 20) {
                    Spacer()

                    Image(systemName: isSearching ? "magnifyingglass" : "note.text")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(theme.textSecondary.opacity(0.5))

                    VStack(spacing: 6) {
                        Text(isSearching ? "ios_tools_memo_search_empty" : "ios_tools_memo_empty_title")
                            .font(.headline)
                            .foregroundStyle(theme.textSecondary)
                        if !isSearching {
                            Text("ios_tools_memo_empty_hint")
                                .font(.subheadline)
                                .foregroundStyle(theme.textSecondary.opacity(0.7))
                        }
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            } else {
                ForEach(visibleMemos) { memo in
                    memoRow(memo)
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            if vault.isPasswordSet && vault.isUnlocked {
                                Button {
                                    toggleEncryption(memo)
                                } label: {
                                    Label(memo.isEncrypted ? "ios_tools_memo_decrypt" : "ios_tools_memo_encrypt",
                                          systemImage: memo.isEncrypted ? "lock.open" : "lock")
                                }
                                .tint(memo.isEncrypted ? .orange : .blue)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                modelContext.delete(memo)
                            } label: {
                                Label("ios_tools_memo_delete", systemImage: "trash")
                            }

                            Button {
                                editingMemo = memo
                            } label: {
                                Label("ios_tools_memo_edit", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
            .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("ios_tools_memo")
        .toolbarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .iosToolNavigationChrome(theme, showsBackButton: true)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("ios_tools_memo")
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                    .onTapGesture {
                        handleTitleTap()
                    }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingNewMemo = true
                } label: {
                    Image(systemName: "plus")
                        .iosToolToolbarIcon(theme)
                }
            }

            ToolbarItem(placement: .bottomBar) {
                Spacer()
            }

            ToolbarItem(placement: .bottomBar) {
                Button {
                    withAnimation { isSearching.toggle(); searchText = "" }
                } label: {
                    Image(systemName: isSearching ? "xmark.circle.fill" : "magnifyingglass")
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
        .navigationDestination(isPresented: $isShowingNewMemo) {
            IOSMemoEditView(vault: vault)
        }
        .navigationDestination(item: $editingMemo) { memo in
            IOSMemoEditView(vault: vault, memo: memo)
        }
        .sheet(isPresented: $showPasswordSheet) {
            IOSMemoPasswordSheet(vault: vault, mode: passwordSheetMode, memos: memos) {
                showPasswordSheet = false
            }
        }
        .sheet(isPresented: $showSecurityPicker) {
            IOSSecurityPickerSheet(vault: vault) { mode in
                showSecurityPicker = false
                if mode == .password {
                    passwordSheetMode = .setPassword
                    showPasswordSheet = true
                }
                // .faceId handled inside the picker sheet
            }
        }
        .alert("ios_tools_memo_destroy_title", isPresented: $showDestroyAlert) {
            Button("ios_tools_memo_destroy_confirm", role: .destructive) {
                destroyAllMemos()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("ios_tools_memo_destroy_message")
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func memoRow(_ memo: IOSMemoItem) -> some View {
        Button {
            editingMemo = memo
        } label: {
            HStack {
                Text(memo.title.isEmpty ? String(localized: "ios_tools_memo_placeholder") : memo.title)
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)

                Spacer()

                if memo.isEncrypted {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(theme.brandPrimary)
                }

                Text(memo.updatedAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .iosGlassContainer(theme, cornerRadius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(theme.borderSubtle, lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func toggleEncryption(_ memo: IOSMemoItem) {
        if memo.isEncrypted {
            if let encrypted = memo.encryptedData {
                memo.content = vault.decrypt(encrypted) ?? memo.content
                memo.encryptedData = nil
            }
            memo.isEncrypted = false
        } else {
            if !memo.content.isEmpty {
                memo.encryptedData = vault.encrypt(memo.content)
                memo.content = ""
            }
            memo.isEncrypted = true
        }
    }

    private func handleTitleTap() {
        tapCount += 1
        tapTimer?.invalidate()
        tapTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
            tapCount = 0
        }

        guard tapCount >= 3 else { return }
        tapCount = 0
        tapTimer?.invalidate()

        if vault.isPasswordSet && vault.isUnlocked {
            vault.lock()
        } else if vault.isPasswordSet {
            if vault.securityMode == .faceId {
                Task { await vault.unlockWithFaceId() }
            } else {
                passwordSheetMode = .unlock
                showPasswordSheet = true
            }
        } else {
            showSecurityPicker = true
        }
    }

    private func destroyAllMemos() {
        for memo in memos {
            modelContext.delete(memo)
        }
        vault.removeSecurity()
    }
}

struct IOSMemoEditView: View {
    @Environment(\.themeTokens) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vault: IOSMemoVault
    @State var memo: IOSMemoItem?

    @State private var title = ""
    @State private var content = ""

    var body: some View {
        VStack(spacing: 16) {
            TextField("ios_tools_memo_title", text: $title)
                .font(.headline)
                .padding(12)
                .iosGlassContainer(theme, cornerRadius: 14)

            TextEditor(text: $content)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(12)
                .iosGlassContainer(theme, cornerRadius: 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(theme.borderSubtle, lineWidth: 1)
                )
        }
        .padding(16)
        .background(Color.clear)
            .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .iosToolNavigationChrome(theme, showsBackButton: true)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("ios_tools_memo_save") {
                    saveMemo()
                }
                .font(.headline.weight(.semibold))
                .disabled(title.isEmpty && content.isEmpty)
            }
        }
        .onAppear {
            loadMemo()
        }
    }

    private func loadMemo() {
        guard let memo else { return }
        title = memo.title

        if let encrypted = memo.encryptedData, vault.isUnlocked {
            content = vault.decrypt(encrypted) ?? memo.content
        } else {
            content = memo.content
        }
    }

    private func saveMemo() {
        let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? content.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? ""
            : title

        if let existing = memo {
            existing.title = finalTitle
            existing.updatedAt = Date()

            if existing.isEncrypted, vault.isUnlocked {
                existing.encryptedData = vault.encrypt(content)
                existing.content = ""
            } else if !existing.isEncrypted {
                existing.content = content
                existing.encryptedData = nil
            }
        } else {
            let newMemo = IOSMemoItem(title: finalTitle, content: content)
            modelContext.insert(newMemo)
        }

        dismiss()
    }
}

struct IOSMemoPasswordSheet: View {
    @Environment(\.themeTokens) private var theme
    @ObservedObject var vault: IOSMemoVault
    let mode: PasswordMode
    let memos: [IOSMemoItem]
    let onDismiss: () -> Void

    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var showDestroyAlert = false

    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: mode == .setPassword ? "key.fill" : "lock.open.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(theme.brandPrimary)
                    .padding(.top, 16)

                Text(mode == .setPassword ? "ios_tools_memo_set_password" : "ios_tools_memo_unlock")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)

                SecureField("ios_tools_memo_password_hint", text: $password)
                    .textInputAutocapitalization(.never)
                    .padding(14)
                    .iosGlassContainer(theme, cornerRadius: 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(theme.borderSubtle, lineWidth: 1)
                    )
                    .focused($isFocused)

                if mode == .setPassword {
                    SecureField("ios_tools_memo_confirm_password", text: $confirmPassword)
                        .textInputAutocapitalization(.never)
                        .padding(14)
                        .iosGlassContainer(theme, cornerRadius: 14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(theme.borderSubtle, lineWidth: 1)
                        )
                }

                if mode == .setPassword {
                    Label("ios_tools_memo_security_warning", systemImage: "exclamationmark.shield.trianglebadge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(theme.danger)
                }

                Button {
                    submit()
                } label: {
                    Text(mode == .setPassword ? "ios_tools_memo_set_password" : "ios_tools_memo_unlock")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.brandPrimary)
                .disabled(password.isEmpty || (mode == .setPassword && (confirmPassword.isEmpty || password != confirmPassword)))

                if mode == .unlock {
                    Button("ios_tools_memo_remove_password") {
                        removePasswordAndDismiss()
                    }
                    .font(.subheadline)
                    .foregroundStyle(theme.danger)
                    .disabled(password.isEmpty)
                }

                Spacer()
            }
            .padding(20)
            .background(Color.clear)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationTitle(mode == .setPassword ? "ios_tools_memo_set_password" : "ios_tools_memo_unlock")
            .navigationBarTitleDisplayMode(.inline)
            .iosToolNavigationChrome(theme)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            isFocused = true
        }
        .alert("ios_tools_memo_destroy_title", isPresented: $showDestroyAlert) {
            Button("ios_tools_memo_destroy_confirm", role: .destructive) {
                onDismiss()
            }
            Button("Cancel", role: .cancel) {
                password = ""
                errorMessage = nil
            }
        } message: {
            Text("ios_tools_memo_destroy_message")
        }
    }

    private func submit() {
        switch mode {
        case .setPassword:
            guard password == confirmPassword else {
                errorMessage = String(localized: "ios_tools_memo_password_mismatch")
                return
            }
            vault.setPassword(password)
            onDismiss()

        case .unlock:
            let result = vault.unlock(with: password)
            switch result {
            case .success:
                onDismiss()
            case .wrong:
                let attempts = UserDefaults.standard.integer(forKey: "memo.vault.failedAttempts")
                let remaining = 5 - attempts
                errorMessage = String(format: String(localized: "ios_tools_memo_wrong_password"), remaining)
                password = ""
            case .destroyed:
                showDestroyAlert = true
            }
        }
    }

    private func removePasswordAndDismiss() {
        if !vault.isUnlocked {
            guard !password.isEmpty, vault.unlock(with: password) == .success else {
                errorMessage = String(localized: "ios_tools_memo_wrong_password_single")
                return
            }
        }
        for memo in memos {
            if let encrypted = memo.encryptedData {
                memo.content = vault.decrypt(encrypted) ?? memo.content
                memo.encryptedData = nil
                memo.isEncrypted = false
            }
        }
        vault.removeSecurity()
        onDismiss()
    }

    enum PasswordMode {
        case setPassword, unlock
    }
}

// MARK: - Security Picker

struct IOSSecurityPickerSheet: View {
    @Environment(\.themeTokens) private var theme
    @ObservedObject var vault: IOSMemoVault
    let onPick: (IOSSecurityMode) -> Void

    @State private var faceIdError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(theme.brandPrimary)
                    .padding(.top, 16)

                Text("ios_memo_security_pick_title")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)

                VStack(spacing: 12) {
                    Button {
                        Task {
                            let result = await vault.setupFaceId()
                            switch result {
                            case .success:
                                onPick(.faceId)
                            case .notAvailable:
                                faceIdError = String(localized: "ios_memo_faceid_not_available")
                            case .canceled:
                                break
                            case .failed(let msg):
                                faceIdError = msg
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "faceid")
                                .font(.title2)
                                .foregroundStyle(theme.brandPrimary)
                                .frame(width: 40)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("ios_memo_security_faceid")
                                    .font(.headline)
                                    .foregroundStyle(theme.textPrimary)
                                Text("ios_memo_security_faceid_desc")
                                    .font(.caption)
                                    .foregroundStyle(theme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(theme.textSecondary)
                        }
                        .padding(14)
                        .iosGlassContainer(theme, cornerRadius: 14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(theme.borderSubtle, lineWidth: 1)
                        )
                    }

                    Button {
                        onPick(.password)
                    } label: {
                        HStack {
                            Image(systemName: "key.fill")
                                .font(.title2)
                                .foregroundStyle(theme.brandPrimary)
                                .frame(width: 40)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("ios_memo_security_password")
                                    .font(.headline)
                                    .foregroundStyle(theme.textPrimary)
                                Text("ios_memo_security_password_desc")
                                    .font(.caption)
                                    .foregroundStyle(theme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(theme.textSecondary)
                        }
                        .padding(14)
                        .iosGlassContainer(theme, cornerRadius: 14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(theme.borderSubtle, lineWidth: 1)
                        )
                    }
                }

                if let error = faceIdError {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(theme.danger)
                }

                Spacer()
            }
            .padding(20)
            .background(Color.clear)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationTitle("ios_memo_security_pick_title")
            .navigationBarTitleDisplayMode(.inline)
            .iosToolNavigationChrome(theme)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        onPick(.none)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
