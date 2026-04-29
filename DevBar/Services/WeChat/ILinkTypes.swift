// ILinkTypes.swift
// DevBar

import AppKit
import CoreImage.CIFilterBuiltins
import Foundation

// MARK: - Constants

enum ILink {
    nonisolated static let baseURL = "https://ilinkai.weixin.qq.com"

    enum MessageType {
        nonisolated static let user = 1
        nonisolated static let bot = 2
    }

    enum MessageState {
        nonisolated static let `new` = 0
        nonisolated static let generating = 1
        nonisolated static let finish = 2
    }

    enum ItemType {
        nonisolated static let text = 1
        nonisolated static let image = 2
        nonisolated static let voice = 3
        nonisolated static let file = 4
        nonisolated static let video = 5
    }

    enum CDNMediaType {
        nonisolated static let image = 1
        nonisolated static let video = 2
        nonisolated static let file = 3
    }

    enum TypingStatus {
        nonisolated static let typing = 1
        nonisolated static let cancel = 2
    }
}

// MARK: - Auth

struct QRCodeResponse: Decodable, Sendable {
    let qrcode: String
    let qrcodeImgContent: String

    enum CodingKeys: String, CodingKey {
        case qrcode
        case qrcodeImgContent = "qrcode_img_content"
    }

    var qrImageData: Data? {
        print("[WeChat:QR] raw qrcode_img_content length=\(qrcodeImgContent.count), prefix=\(String(qrcodeImgContent.prefix(80)))")

        let rawContent = qrcodeImgContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawContent.hasPrefix("http://") || rawContent.hasPrefix("https://") {
            print("[WeChat:QR] qrcode_img_content is URL, generating QR image")
            return Self.makeQRCodePNGData(from: rawContent)
        }

        var base64Str = rawContent

        // Strip data URI prefix if present: "data:image/png;base64,..."
        if let range = base64Str.range(of: ";base64,") {
            base64Str = String(base64Str[range.upperBound...])
            print("[WeChat:QR] stripped data URI prefix (;base64,)")
        } else if let range = base64Str.range(of: ",") {
            base64Str = String(base64Str[range.upperBound...])
            print("[WeChat:QR] stripped comma prefix")
        }

        // Strip whitespace/newlines
        base64Str = base64Str.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")

        print("[WeChat:QR] cleaned base64 length=\(base64Str.count), first 40 chars=\(String(base64Str.prefix(40)))")

        let data = Data(base64Encoded: base64Str)
        if let data {
            print("[WeChat:QR] decoded OK, image data size=\(data.count) bytes")
        } else {
            print("[WeChat:QR] base64 decode FAILED, raw length=\(base64Str.count)")
            // Try stripping all non-base64 characters as last resort
            let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
            let filtered = base64Str.components(separatedBy: allowed.inverted).joined()
            if filtered != base64Str {
                print("[WeChat:QR] retrying with filtered base64, length=\(filtered.count)")
                if let retryData = Data(base64Encoded: filtered) {
                    print("[WeChat:QR] retry decode OK, image data size=\(retryData.count) bytes")
                    return retryData
                }
            }
        }
        return data
    }

    private static func makeQRCodePNGData(from value: String) -> Data? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else {
            print("[WeChat:QR] QR filter output is nil")
            return nil
        }

        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else {
            print("[WeChat:QR] failed to render QR CGImage")
            return nil
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let pngData = bitmap.representation(using: .png, properties: [:])
        if let pngData {
            print("[WeChat:QR] generated QR PNG size=\(pngData.count) bytes")
        } else {
            print("[WeChat:QR] failed to encode QR PNG")
        }
        return pngData
    }
}

struct QRStatusResponse: Decodable, Sendable {
    let status: String
    let botToken: String?
    let ilinkBotID: String?
    let baseurl: String?
    let ilinkUserID: String?

    enum CodingKeys: String, CodingKey {
        case status
        case botToken = "bot_token"
        case ilinkBotID = "ilink_bot_id"
        case baseurl
        case ilinkUserID = "ilink_user_id"
    }

    var isConfirmed: Bool { status == "confirmed" }
    var isExpired: Bool { status == "expired" }
    var isScanned: Bool { status == "scaned" }
    var isWaiting: Bool { status == "wait" }
}

struct ILinkCredentials: Codable, Sendable {
    let botToken: String
    let ilinkBotID: String
    let baseurl: String
    let ilinkUserID: String

    enum CodingKeys: String, CodingKey {
        case botToken = "bot_token"
        case ilinkBotID = "ilink_bot_id"
        case baseurl
        case ilinkUserID = "ilink_user_id"
    }

    nonisolated var effectiveBaseURL: String {
        baseurl.isEmpty ? ILink.baseURL : baseurl
    }
}

// MARK: - Messages

struct BaseInfo: Encodable, Sendable {
    let channelVersion: String?

    enum CodingKeys: String, CodingKey {
        case channelVersion = "channel_version"
    }
}

nonisolated struct GetUpdatesRequest: Encodable, Sendable {
    let getUpdatesBuf: String
    let baseInfo: BaseInfo

    enum CodingKeys: String, CodingKey {
        case getUpdatesBuf = "get_updates_buf"
        case baseInfo = "base_info"
    }
}

nonisolated struct GetUpdatesResponse: Decodable, Sendable {
    let ret: Int?
    let errcode: Int?
    let errmsg: String?
    let msgs: [WeixinMessage]?
    let getUpdatesBuf: String?
    let longpollingTimeoutMs: Int?

    enum CodingKeys: String, CodingKey {
        case ret, errcode, errmsg, msgs
        case getUpdatesBuf = "get_updates_buf"
        case longpollingTimeoutMs = "longpolling_timeout_ms"
    }

    var isSuccess: Bool { ret == nil || ret == 0 }
    var isSessionExpired: Bool { errcode == -14 }
}

struct WeixinMessage: Decodable, Identifiable, Sendable {
    var id: Int { seq ?? 0 }

    let seq: Int?
    let messageID: Int64?
    let fromUserID: String?
    let toUserID: String?
    let messageType: Int?
    let messageState: Int?
    let itemList: [MessageItem]?
    let contextToken: String?
    let createTimeMs: Int64?

    enum CodingKeys: String, CodingKey {
        case seq
        case messageID = "message_id"
        case fromUserID = "from_user_id"
        case toUserID = "to_user_id"
        case messageType = "message_type"
        case messageState = "message_state"
        case itemList = "item_list"
        case contextToken = "context_token"
        case createTimeMs = "create_time_ms"
    }

    var isFromUser: Bool { messageType == ILink.MessageType.user }
    var textContent: String? {
        itemList?.first(where: { $0.type == ILink.ItemType.text })?.textItem?.text
    }
}

nonisolated struct MessageItem: Decodable, Encodable, Sendable {
    let type: Int
    let textItem: TextItem?
    let imageItem: EncodableImageItem?
    let voiceItem: EncodableVoiceItem?
    let videoItem: EncodableVideoItem?
    let fileItem: EncodableFileItem?

    enum CodingKeys: String, CodingKey {
        case type
        case textItem = "text_item"
        case imageItem = "image_item"
        case voiceItem = "voice_item"
        case videoItem = "video_item"
        case fileItem = "file_item"
    }

    init(type: Int, textItem: TextItem? = nil, imageItem: EncodableImageItem? = nil) {
        self.type = type
        self.textItem = textItem
        self.imageItem = imageItem
        self.voiceItem = nil
        self.videoItem = nil
        self.fileItem = nil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(Int.self, forKey: .type)
        textItem = try c.decodeIfPresent(TextItem.self, forKey: .textItem)
        imageItem = try c.decodeIfPresent(EncodableImageItem.self, forKey: .imageItem)
        voiceItem = try c.decodeIfPresent(EncodableVoiceItem.self, forKey: .voiceItem)
        videoItem = try c.decodeIfPresent(EncodableVideoItem.self, forKey: .videoItem)
        fileItem = try c.decodeIfPresent(EncodableFileItem.self, forKey: .fileItem)
    }
}

nonisolated struct TextItem: Decodable, Encodable, Sendable {
    let text: String
}

// Decodable-only types for incoming messages
struct ImageItem: Decodable, Sendable {
    let url: String?
    let media: MediaInfo?
    let midSize: Int?

    enum CodingKeys: String, CodingKey {
        case url, media
        case midSize = "mid_size"
    }
}

struct VoiceItem: Decodable, Sendable {
    let media: MediaInfo?
    let voiceSize: Int?
    let encodeType: Int?
    let playtime: Int?
    let text: String?

    enum CodingKeys: String, CodingKey {
        case media, text
        case voiceSize = "voice_size"
        case encodeType = "encode_type"
        case playtime
    }
}

struct VideoItem: Decodable, Sendable {
    let media: MediaInfo?
    let videoSize: Int?

    enum CodingKeys: String, CodingKey {
        case media
        case videoSize = "video_size"
    }
}

struct FileItem: Decodable, Sendable {
    let media: MediaInfo?
    let fileName: String?
    let len: String?

    enum CodingKeys: String, CodingKey {
        case media
        case fileName = "file_name"
        case len
    }
}

// Encodable wrappers for outgoing messages
typealias EncodableImageItem = ImageItem
typealias EncodableVoiceItem = VoiceItem
typealias EncodableVideoItem = VideoItem
typealias EncodableFileItem = FileItem

// ImageItem needs Encodable for outgoing
extension ImageItem: Encodable {}
extension VoiceItem: Encodable {}
extension VideoItem: Encodable {}
extension FileItem: Encodable {}

struct MediaInfo: Decodable, Encodable, Sendable {
    let encryptQueryParam: String?
    let aesKey: String?
    let encryptType: Int?

    enum CodingKeys: String, CodingKey {
        case encryptQueryParam = "encrypt_query_param"
        case aesKey = "aes_key"
        case encryptType = "encrypt_type"
    }
}

// MARK: - Send

nonisolated struct SendMessageRequest: Encodable, Sendable {
    let msg: SendMsg
    let baseInfo: BaseInfo

    enum CodingKeys: String, CodingKey {
        case msg, baseInfo = "base_info"
    }
}

struct SendMsg: Encodable, Sendable {
    let fromUserID: String
    let toUserID: String
    let clientID: String
    let messageType: Int
    let messageState: Int
    let itemList: [MessageItem]
    let contextToken: String?

    enum CodingKeys: String, CodingKey {
        case fromUserID = "from_user_id"
        case toUserID = "to_user_id"
        case clientID = "client_id"
        case messageType = "message_type"
        case messageState = "message_state"
        case itemList = "item_list"
        case contextToken = "context_token"
    }
}

nonisolated struct SendMessageResponse: Decodable, Sendable {
    let ret: Int?
    let errmsg: String?

    var isSuccess: Bool { ret == nil || ret == 0 }
}

// MARK: - Upload

nonisolated struct GetUploadURLRequest: Encodable, Sendable {
    let fileKey: String
    let mediaType: Int
    let toUserID: String
    let rawSize: Int
    let rawFileMD5: String
    let fileSize: Int
    let noNeedThumb: Bool
    let aesKey: String
    let baseInfo: BaseInfo

    enum CodingKeys: String, CodingKey {
        case fileKey = "filekey"
        case mediaType = "media_type"
        case toUserID = "to_user_id"
        case rawSize = "rawsize"
        case rawFileMD5 = "rawfilemd5"
        case fileSize = "filesize"
        case noNeedThumb = "no_need_thumb"
        case aesKey = "aeskey"
        case baseInfo = "base_info"
    }
}

nonisolated struct GetUploadURLResponse: Decodable, Sendable {
    let ret: Int
    let errmsg: String?
    let uploadParam: String?
    let uploadFullURL: String?

    enum CodingKeys: String, CodingKey {
        case ret, errmsg
        case uploadParam = "upload_param"
        case uploadFullURL = "upload_full_url"
    }

    var isSuccess: Bool { ret == 0 }
}

// MARK: - Config / Typing

nonisolated struct GetConfigRequest: Encodable, Sendable {
    let ilinkUserID: String
    let contextToken: String?
    let baseInfo: BaseInfo

    enum CodingKeys: String, CodingKey {
        case ilinkUserID = "ilink_user_id"
        case contextToken = "context_token"
        case baseInfo = "base_info"
    }
}

nonisolated struct GetConfigResponse: Decodable, Sendable {
    let ret: Int
    let errmsg: String?
    let typingTicket: String?

    enum CodingKeys: String, CodingKey {
        case ret, errmsg
        case typingTicket = "typing_ticket"
    }
}

nonisolated struct SendTypingRequest: Encodable, Sendable {
    let ilinkUserID: String
    let typingTicket: String
    let status: Int
    let baseInfo: BaseInfo

    enum CodingKeys: String, CodingKey {
        case ilinkUserID = "ilink_user_id"
        case typingTicket = "typing_ticket"
        case status
        case baseInfo = "base_info"
    }
}

nonisolated struct SendTypingResponse: Decodable, Sendable {
    let ret: Int
    let errmsg: String?
}
