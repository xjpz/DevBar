// WeChatAuthService.swift
// DevBar

import Combine
import Foundation

@MainActor
final class WeChatAuthService: ObservableObject {
    @Published var accounts: [ILinkCredentials] = []
    @Published var loginState: LoginState = .idle

    enum LoginState: Equatable {
        case idle
        case loading
        case qrReady(Data)
        case waiting
        case scanned
        case confirmed
        case failed(String)
    }

    private enum QRLoginEvent {
        case waiting
        case scanned
        case confirmed(ILinkCredentials)
        case expired
    }

    private let accountsDir: URL
    private var loginTask: Task<Void, Never>?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        accountsDir = home.appendingPathComponent(".weclaw/accounts")
        loadAccounts()
    }

    // MARK: - Account Management

    func loadAccounts() {
        accounts = Self.loadAllCredentials(from: accountsDir)
    }

    func deleteAccount(_ account: ILinkCredentials) {
        let id = Self.normalizeAccountID(account.ilinkBotID)
        let fileURL = accountsDir.appendingPathComponent("\(id).json")
        try? FileManager.default.removeItem(at: fileURL)
        loadAccounts()
    }

    static func accountsDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".weclaw/accounts")
    }

    // MARK: - QR Login

    func startLogin() {
        loginTask?.cancel()
        loginTask = Task { [weak self] in
            guard let self else { return }
            do {
                self.loginState = .loading

                // Fetch QR code
                let qrResp: QRCodeResponse = try await ILinkClient.get(
                    url: "https://ilinkai.weixin.qq.com/ilink/bot/get_bot_qrcode?bot_type=3"
                )

                print("[WeChat:Auth] QR response: qrcode=\(qrResp.qrcode), imgContentLen=\(qrResp.qrcodeImgContent.count)")

                guard let imageData = qrResp.qrImageData else {
                    print("[WeChat:Auth] QR image decode failed — qrImageData returned nil")
                    self.loginState = .failed("Failed to decode QR image")
                    return
                }

                self.loginState = .qrReady(imageData)

                // Poll for scan status
                let statusURL = "https://ilinkai.weixin.qq.com/ilink/bot/get_qrcode_status?qrcode=\(qrResp.qrcode)"

                for try await event in Self.pollStatus(url: statusURL) {
                    guard !Task.isCancelled else { return }
                    switch event {
                    case .waiting:
                        if case .qrReady = self.loginState { /* keep showing QR */ }
                        else { self.loginState = .waiting }
                    case .scanned:
                        self.loginState = .scanned
                    case .confirmed(let credentials):
                        Self.saveCredentials(credentials)
                        self.loadAccounts()
                        self.loginState = .confirmed
                        return
                    case .expired:
                        self.loginState = .failed(String(localized: "wechat_qr_expired"))
                        return
                    }
                }
            } catch is CancellationError {
                self.loginState = .idle
            } catch {
                self.loginState = .failed(error.localizedDescription)
            }
        }
    }

    func cancelLogin() {
        loginTask?.cancel()
        loginState = .idle
    }

    // MARK: - Private

    private static func pollStatus(url: String) -> AsyncStream<QRLoginEvent> {
        AsyncStream { continuation in
            Task {
                let pollClient = URLSession.shared
                let requestURL = URL(string: url)!

                while !Task.isCancelled {
                    do {
                        let (data, _) = try await pollClient.data(from: requestURL)
                        let resp = try JSONDecoder().decode(QRStatusResponse.self, from: data)

                        if resp.isConfirmed {
                            let credentials = ILinkCredentials(
                                botToken: resp.botToken ?? "",
                                ilinkBotID: resp.ilinkBotID ?? "",
                                baseurl: resp.baseurl ?? "",
                                ilinkUserID: resp.ilinkUserID ?? ""
                            )
                            if credentials.botToken.isEmpty {
                                continuation.finish()
                                return
                            }
                            continuation.yield(.confirmed(credentials))
                            continuation.finish()
                            return
                        }
                        if resp.isExpired {
                            continuation.yield(.expired)
                            continuation.finish()
                            return
                        }
                        if resp.isScanned {
                            continuation.yield(.scanned)
                        } else {
                            continuation.yield(.waiting)
                        }
                    } catch {
                        // Network error, retry after delay
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                    }
                }
                continuation.finish()
            }
        }
    }

    static func saveCredentials(_ creds: ILinkCredentials) {
        let dir = Self.accountsDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])

        let id = normalizeAccountID(creds.ilinkBotID)
        let fileURL = dir.appendingPathComponent("\(id).json")

        guard let data = try? JSONEncoder().encode(creds) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func normalizeAccountID(_ raw: String) -> String {
        raw.replacingOccurrences(of: "@", with: "-")
            .replacingOccurrences(of: ".", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    static func loadAllCredentials(from dir: URL) -> [ILinkCredentials] {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        return entries.compactMap { url in
            guard url.pathExtension == "json" else { return nil }
            guard let data = try? Data(contentsOf: url) else { return nil }
            let creds = try? JSONDecoder().decode(ILinkCredentials.self, from: data)
            return creds?.botToken.isEmpty == false ? creds : nil
        }
    }
}
