import DevBarCore
import SwiftData
import SwiftUI

struct IOSTerminalServerListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.themeTokens) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.iosToolEntryContext) private var toolEntryContext
    @Query(sort: \IOSTerminalServer.updatedAt, order: .reverse) private var servers: [IOSTerminalServer]
    @State private var editorMode: IOSTerminalServerEditorMode?
    @State private var openConnectionIDs: Set<UUID> = []

    private let credentialStore = TerminalCredentialStore()
    private let sessionRegistry = IOSTerminalSessionRegistry.shared

    var body: some View {
        Group {
            if servers.isEmpty {
                terminalEmptyState
            } else {
                serverList
            }
        }
        .background(terminalPageBackground.ignoresSafeArea())
        .navigationTitle("Terminal")
        .iosToolTitleDisplayMode(toolEntryContext)
        .toolbar(toolEntryContext.tabBarVisibility, for: .tabBar)
        .iosToolNavigationChrome(theme, showsBackButton: toolEntryContext.showsBackButton)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorMode = .add
                } label: {
                    Image(systemName: "plus")
                        .iosToolToolbarIcon(theme)
                }
                .accessibilityLabel("Add Server")
            }
        }
        .sheet(item: $editorMode) { mode in
            NavigationStack {
                IOSTerminalServerEditorView(mode: mode)
            }
        }
        .onAppear {
            refreshOpenConnections()
        }
        .accessibilityIdentifier("ios.tools.terminal.servers")
    }

    private var serverList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(servers) { server in
                    HStack(spacing: 8) {
                        NavigationLink {
                            IOSTerminalSessionView(server: server)
                        } label: {
                            IOSTerminalServerRow(server: server, theme: theme)
                        }
                        .buttonStyle(.plain)

                        Menu {
                            Button {
                                editorMode = .edit(server)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                delete(server)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            if openConnectionIDs.contains(server.id) {
                                Button {
                                    close(server)
                                } label: {
                                    Label("Close", systemImage: "xmark.circle")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(theme.textTertiary)
                                .frame(width: 34, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Server Actions")
                    }
                    .padding(.trailing, 6)
                    .iosGlassContainer(theme, cornerRadius: 18)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
    }

    private var terminalEmptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(theme.brandPrimary)
                .frame(width: 72, height: 72)
                .background(theme.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(spacing: 6) {
                Text("No Servers")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                Text("Add a server configuration to start an SSH terminal.")
                    .font(theme.subheadlineFont)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(theme.textSecondary)
            }

            Button {
                editorMode = .add
            } label: {
                Label("Add Server", systemImage: "plus")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.brandPrimary)
            .padding(.horizontal, 28)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var terminalPageBackground: Color {
        theme.isGeek || colorScheme == .dark ? .black : theme.backgroundSecondary
    }

    private func delete(_ server: IOSTerminalServer) {
        sessionRegistry.closeSession(serverID: server.id)
        refreshOpenConnections()
        credentialStore.deleteSecrets(serverID: server.id)
        modelContext.delete(server)
    }

    private func close(_ server: IOSTerminalServer) {
        sessionRegistry.closeSession(serverID: server.id)
        refreshOpenConnections()
    }

    private func refreshOpenConnections() {
        openConnectionIDs = sessionRegistry.openConnectionIDs()
    }
}

private struct IOSTerminalServerRow: View {
    let server: IOSTerminalServer
    let theme: IOSThemeTokens

    var body: some View {
        HStack(spacing: 12) {
            TerminalOSIconView(family: server.remoteOSFamily, theme: theme)

            VStack(alignment: .leading, spacing: 4) {
                Text(server.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text(server.displayAddress)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                Label(server.authMethod.title, systemImage: server.authMethod.systemImage)
                    .font(theme.caption2Font)
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct TerminalOSIconView: View {
    let family: TerminalRemoteOSFamily
    let theme: IOSThemeTokens

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(iconBackground)

            if let assetName = family.assetName {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .padding(7)
            } else {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.brandPrimary)
            }
        }
        .frame(width: 40, height: 40)
    }

    private var iconBackground: Color {
        if family.assetName == nil {
            return theme.brandPrimary.opacity(0.12)
        }
        return theme.surfaceSecondary.opacity(theme.isGeek ? 0.92 : 1)
    }
}

private extension TerminalRemoteOSFamily {
    var assetName: String? {
        switch self {
        case .almaLinux:
            return "TerminalOSAlmaLinux"
        case .android:
            return "TerminalOSAndroid"
        case .alpine:
            return "TerminalOSAlpine"
        case .arch:
            return "TerminalOSArch"
        case .elementaryOS:
            return "TerminalOSElementaryOS"
        case .feren:
            return "TerminalOSFeren"
        case .freeBSD:
            return "TerminalOSFreeBSD"
        case .garuda:
            return "TerminalOSGaruda"
        case .haiku:
            return "TerminalOSHaiku"
        case .kali:
            return "TerminalOSKali"
        case .linux:
            return "TerminalOSLinux"
        case .linuxMint:
            return "TerminalOSLinuxMint"
        case .macOS:
            return "TerminalOSMacOS"
        case .manjaro:
            return "TerminalOSManjaro"
        case .nixOS:
            return "TerminalOSNixOS"
        case .popOS:
            return "TerminalOSPopOS"
        case .redHat:
            return "TerminalOSRedHat"
        case .rocky:
            return "TerminalOSRocky"
        case .serenityOS:
            return "TerminalOSSerenityOS"
        case .windows:
            return "TerminalOSWindows"
        case .ubuntu:
            return "TerminalOSUbuntu"
        case .debian:
            return "TerminalOSDebian"
        case .centos:
            return "TerminalOSCentOS"
        case .fedora:
            return "TerminalOSFedora"
        case .gentoo:
            return "TerminalOSGentoo"
        case .openSUSE:
            return "TerminalOSOpenSUSE"
        case .auto, .unknown:
            return nil
        }
    }
}

enum IOSTerminalServerEditorMode: Identifiable {
    case add
    case edit(IOSTerminalServer)

    var id: String {
        switch self {
        case .add:
            return "add"
        case let .edit(server):
            return "edit-\(server.id.uuidString)"
        }
    }
}
