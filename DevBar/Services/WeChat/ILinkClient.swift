// ILinkClient.swift
// DevBar

import Foundation

// MARK: - ILink API Client

actor ILinkClient {
    private let baseURL: String
    private let botToken: String
    private let botID: String
    private let wechatUIN: String
    private let session: URLSession

    init(credentials: ILinkCredentials) {
        self.baseURL = credentials.effectiveBaseURL
        self.botToken = credentials.botToken
        self.botID = credentials.ilinkBotID
        self.wechatUIN = Self.generateWechatUIN()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 40
        config.timeoutIntervalForResource = 45
        // Bypass system proxy — iLink API is direct-access in China, proxy causes TLS errors
        config.connectionProxyDictionary = [:]
        self.session = URLSession(configuration: config)
    }

    var currentBotID: String { botID }

    // MARK: - GetUpdates (long-poll)

    func getUpdates(buf: String) async throws -> GetUpdatesResponse {
        let body = GetUpdatesRequest(
            getUpdatesBuf: buf,
            baseInfo: BaseInfo(channelVersion: "1.0.0")
        )
        return try await post("/ilink/bot/getupdates", body: body)
    }

    // MARK: - SendMessage

    func sendText(from fromID: String, to toID: String, text: String, contextToken: String? = nil) async throws -> SendMessageResponse {
        let msg = SendMessageRequest(
            msg: SendMsg(
                fromUserID: fromID,
                toUserID: toID,
                clientID: UUID().uuidString,
                messageType: ILink.MessageType.bot,
                messageState: ILink.MessageState.finish,
                itemList: [MessageItem(type: ILink.ItemType.text, textItem: TextItem(text: text))],
                contextToken: contextToken
            ),
            baseInfo: BaseInfo(channelVersion: "1.0.0")
        )
        return try await post("/ilink/bot/sendmessage", body: msg)
    }

    // MARK: - GetConfig

    func getConfig(userID: String, contextToken: String? = nil) async throws -> GetConfigResponse {
        let body = GetConfigRequest(
            ilinkUserID: userID,
            contextToken: contextToken,
            baseInfo: BaseInfo(channelVersion: nil)
        )
        return try await post("/ilink/bot/getconfig", body: body)
    }

    // MARK: - SendTyping

    func sendTyping(userID: String, ticket: String, status: Int) async throws {
        let body = SendTypingRequest(
            ilinkUserID: userID,
            typingTicket: ticket,
            status: status,
            baseInfo: BaseInfo(channelVersion: nil)
        )
        let resp: SendTypingResponse = try await post("/ilink/bot/sendtyping", body: body)
        if resp.ret != 0 {
            throw ILinkError.apiError(resp.errmsg ?? "sendtyping failed (ret=\(resp.ret))")
        }
    }

    // MARK: - GetUploadURL

    func getUploadURL(fileKey: String, mediaType: Int, toUserID: String, rawSize: Int, rawMD5: String, encryptedSize: Int, aesKey: String) async throws -> GetUploadURLResponse {
        let body = GetUploadURLRequest(
            fileKey: fileKey,
            mediaType: mediaType,
            toUserID: toUserID,
            rawSize: rawSize,
            rawFileMD5: rawMD5,
            fileSize: encryptedSize,
            noNeedThumb: true,
            aesKey: aesKey,
            baseInfo: BaseInfo(channelVersion: "1.0.0")
        )
        return try await post("/ilink/bot/getuploadurl", body: body)
    }

    // MARK: - Generic GET (for auth)

    static func get<T: Decodable>(url: String) async throws -> T {
        guard let requestURL = URL(string: url) else {
            throw ILinkError.invalidURL
        }
        let (data, response) = try await URLSession.shared.data(from: requestURL)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ILinkError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ILinkError.httpError(httpResponse.statusCode, body)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Private

    private func post<T: Decodable>(_ path: String, body: Encodable) async throws -> T {
        guard let url = URL(string: baseURL + path) else {
            throw ILinkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ilink_bot_token", forHTTPHeaderField: "AuthorizationType")
        request.setValue("Bearer \(botToken)", forHTTPHeaderField: "Authorization")
        request.setValue(wechatUIN, forHTTPHeaderField: "X-WECHAT-UIN")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ILinkError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("[WeChat:HTTP] \(path) status=\(httpResponse.statusCode) body=\(body.prefix(200))")
            throw ILinkError.httpError(httpResponse.statusCode, body)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "(non-utf8)"
            print("[WeChat:HTTP] \(path) decode failed: \(error)")
            print("[WeChat:HTTP] \(path) raw response (\(data.count) bytes): \(raw.prefix(500))")
            throw error
        }
    }

    private static func generateWechatUIN() -> String {
        let random = UInt32.random(in: 0...UInt32.max)
        let str = String(random)
        return Data(str.utf8).base64EncodedString()
    }
}

// MARK: - Errors

enum ILinkError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int, String = "")
    case apiError(String)
    case qrExpired
    case sessionExpired
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid response from server"
        case .httpError(let code, let body): return "HTTP \(code): \(body)"
        case .apiError(let msg): return msg
        case .qrExpired: return String(localized: "wechat_qr_expired")
        case .sessionExpired: return String(localized: "wechat_session_expired")
        case .cancelled: return "Cancelled"
        }
    }
}
