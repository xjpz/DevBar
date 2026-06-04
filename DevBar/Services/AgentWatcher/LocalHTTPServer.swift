import Foundation
import Network

// MARK: - HTTP Request

struct HTTPRequest: Equatable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data?

    var bodyString: String? {
        body.flatMap { String(data: $0, encoding: .utf8) }
    }
}

enum LocalHTTPRequestParseResult: Equatable {
    case incomplete
    case request(HTTPRequest)
    case invalid
}

struct LocalHTTPRequestParser {
    private static let headerSeparator = Data("\r\n\r\n".utf8)
    private static let maximumRequestSize = 64 * 1024

    private var buffer = Data()

    mutating func append(_ data: Data) -> LocalHTTPRequestParseResult {
        guard buffer.count + data.count <= Self.maximumRequestSize else {
            return .invalid
        }
        buffer.append(data)

        guard let separatorRange = buffer.range(of: Self.headerSeparator) else {
            return .incomplete
        }
        guard let headerString = String(data: buffer[..<separatorRange.lowerBound], encoding: .utf8) else {
            return .invalid
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return .invalid
        }
        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard requestParts.count == 3 else {
            return .invalid
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colonIndex = line.firstIndex(of: ":") else {
                return .invalid
            }
            let name = String(line[..<colonIndex]).lowercased()
            let value = String(line[line.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let contentLength: Int
        if let value = headers["content-length"] {
            guard let parsedLength = Int(value), parsedLength >= 0 else {
                return .invalid
            }
            contentLength = parsedLength
        } else {
            contentLength = 0
        }

        let bodyStart = separatorRange.upperBound
        let bodyEnd = bodyStart + contentLength
        guard bodyEnd <= Self.maximumRequestSize else {
            return .invalid
        }
        guard buffer.count >= bodyEnd else {
            return .incomplete
        }

        let body = contentLength > 0 ? Data(buffer[bodyStart..<bodyEnd]) : nil
        return .request(
            HTTPRequest(
                method: String(requestParts[0]).uppercased(),
                path: String(requestParts[1]),
                headers: headers,
                body: body
            )
        )
    }
}

// MARK: - HTTP Response

struct HTTPResponse {
    let statusCode: Int
    let headers: [String: String]
    let body: Data?

    init(statusCode: Int, headers: [String: String] = [:], body: Data? = nil) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    init(statusCode: Int, json: [String: Any]) {
        self.statusCode = statusCode
        self.headers = ["Content-Type": "application/json"]
        self.body = try? JSONSerialization.data(withJSONObject: json)
    }
}

// MARK: - Route Handler

typealias RouteHandler = (HTTPRequest) -> HTTPResponse

// MARK: - Local HTTP Server

class LocalHTTPServer {
    private let port: UInt16
    private var listener: NWListener?
    private var routes: [String: RouteHandler] = [:]
    private let queue = DispatchQueue(label: "com.devbar.agentwatcher.httpserver", qos: .userInitiated)

    var onRequest: ((HTTPRequest) -> HTTPResponse)?
    var onStateChange: ((NWListener.State) -> Void)?

    init(port: UInt16 = 49321) {
        self.port = port
    }

    // MARK: - Server Lifecycle

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(
            host: .ipv4(IPv4Address("127.0.0.1")!),
            port: NWEndpoint.Port(rawValue: port)!
        )

        listener = try NWListener(using: parameters)

        listener?.stateUpdateHandler = { [weak self] state in
            self?.onStateChange?(state)
            switch state {
            case .ready:
                print("[HTTPServer] Listening on port \(self?.port ?? 0)")
            case .failed(let error):
                print("[HTTPServer] Failed: \(error)")
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        print("[HTTPServer] Stopped")
    }

    // MARK: - Route Registration

    func registerRoute(_ method: String, _ path: String, handler: @escaping RouteHandler) {
        routes[routeKey(method: method, path: path)] = handler
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)

        receiveRequest(connection: connection, parser: LocalHTTPRequestParser())
    }

    private func receiveRequest(connection: NWConnection, parser: LocalHTTPRequestParser) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self, error == nil else {
                connection.cancel()
                return
            }

            var updatedParser = parser
            switch updatedParser.append(data ?? Data()) {
            case .request(let request):
                let response = self.routeRequest(request)
                self.sendResponse(response, to: connection)
            case .incomplete where !isComplete:
                self.receiveRequest(connection: connection, parser: updatedParser)
            case .incomplete, .invalid:
                let response = HTTPResponse(statusCode: 400, json: ["error": "Bad Request"])
                self.sendResponse(response, to: connection)
            }
        }
    }

    // MARK: - Routing

    private func routeRequest(_ request: HTTPRequest) -> HTTPResponse {
        // 检查注册的路由
        let exactRoute = routeKey(method: request.method, path: request.path)
        if let handler = routes[exactRoute] {
            return handler(request)
        }

        // 检查通配路由
        for (pattern, handler) in routes {
            if matchPattern(pattern, exactRoute) {
                return handler(request)
            }
        }

        if routes.keys.contains(where: { registeredRoute in
            registeredRoute.split(separator: " ", maxSplits: 1).last.map(String.init) == request.path
        }) {
            return HTTPResponse(statusCode: 405, json: ["error": "Method Not Allowed"])
        }

        // 默认 404
        return HTTPResponse(statusCode: 404, json: ["error": "Not Found"])
    }

    private func matchPattern(_ pattern: String, _ path: String) -> Bool {
        // 简单的通配符匹配
        if pattern.hasSuffix("/*") {
            let prefix = String(pattern.dropLast(2))
            return path.hasPrefix(prefix)
        }
        return pattern == path
    }

    private func routeKey(method: String, path: String) -> String {
        "\(method.uppercased()) \(path)"
    }

    // MARK: - Response Sending

    private func sendResponse(_ response: HTTPResponse, to connection: NWConnection) {
        var httpResponse = "HTTP/1.1 \(response.statusCode) \(statusCodeDescription(response.statusCode))\r\n"

        for (key, value) in response.headers {
            httpResponse += "\(key): \(value)\r\n"
        }

        if let body = response.body {
            httpResponse += "Content-Length: \(body.count)\r\n"
        } else {
            httpResponse += "Content-Length: 0\r\n"
        }

        httpResponse += "Connection: close\r\n"
        httpResponse += "\r\n"

        var data = httpResponse.data(using: .utf8) ?? Data()
        if let body = response.body {
            data.append(body)
        }

        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func statusCodeDescription(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 405: return "Method Not Allowed"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default: return "Unknown"
        }
    }
}
