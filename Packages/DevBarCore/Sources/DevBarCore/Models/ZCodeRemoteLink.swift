import Foundation

/// zcode 桌面端「移动端远程控制」连接地址。
///
/// 地址自带远控授权（`sid` + `hash`），等同远控钥匙：
/// 任何日志、报错、UI 不得完整输出该地址。
public struct ZCodeRemoteLink: Equatable, Sendable {
    /// 官方远控页面与官网同域名。
    public static let allowedHost = "zcode.z.ai"

    /// 路径带版本段（如 `/remote/v4`），按前缀放行以免桌面端升级版本后失效。
    static let requiredPathPrefix = "/remote/"

    public let url: URL
    /// 桌面主机名（`name` 参数，非敏感），仅用于配对确认页展示。
    public let desktopName: String?

    public init?(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed) else {
            return nil
        }

        guard url.scheme?.lowercased() == "https" else {
            return nil
        }

        guard let host = url.host?.lowercased(), host == Self.allowedHost else {
            return nil
        }

        guard url.path.hasPrefix(Self.requiredPathPrefix) else {
            return nil
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return nil
        }

        let queryByName = Dictionary(queryItems.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        guard let sid = queryByName["sid"], !sid.isEmpty,
              let hash = queryByName["hash"], !hash.isEmpty else {
            return nil
        }

        self.url = url
        self.desktopName = queryByName["name"].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// 脱敏描述，仅到域名层级，不含任何凭据。
    public var maskedDescription: String {
        "https://\(Self.allowedHost)/remote/…"
    }
}
