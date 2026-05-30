import Foundation
import Network

// MARK: - HTTP Request

struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data?

    var bodyString: String? {
        body.flatMap { String(data: $0, encoding: .utf8) }
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

    init(port: UInt16 = 49321) {
        self.port = port
    }

    // MARK: - Server Lifecycle

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)

        listener?.stateUpdateHandler = { [weak self] state in
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

    func registerRoute(_ path: String, handler: @escaping RouteHandler) {
        routes[path] = handler
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)

        receiveRequest(connection: connection)
    }

    private func receiveRequest(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self, let data = data, !data.isEmpty else {
                connection.cancel()
                return
            }

            if let request = self.parseHTTPRequest(data) {
                let response = self.routeRequest(request)
                self.sendResponse(response, to: connection)
            } else {
                let response = HTTPResponse(statusCode: 400, json: ["error": "Bad Request"])
                self.sendResponse(response, to: connection)
            }

            if isComplete {
                connection.cancel()
            }
        }
    }

    // MARK: - HTTP Parsing

    private func parseHTTPRequest(_ data: Data) -> HTTPRequest? {
        guard let string = String(data: data, encoding: .utf8) else { return nil }

        let parts = string.components(separatedBy: "\r\n\r\n")
        guard let headerPart = parts.first else { return nil }

        let headerLines = headerPart.components(separatedBy: "\r\n")
        guard let firstLine = headerLines.first else { return nil }

        let firstLineComponents = firstLine.components(separatedBy: " ")
        guard firstLineComponents.count >= 2 else { return nil }

        let method = firstLineComponents[0]
        let path = firstLineComponents[1]

        var headers: [String: String] = [:]
        for i in 1..<headerLines.count {
            let line = headerLines[i]
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        let body: Data? = parts.count > 1 ? parts[1].data(using: .utf8) : nil

        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }

    // MARK: - Routing

    private func routeRequest(_ request: HTTPRequest) -> HTTPResponse {
        // 检查注册的路由
        if let handler = routes[request.path] {
            return handler(request)
        }

        // 检查通配路由
        for (pattern, handler) in routes {
            if matchPattern(pattern, request.path) {
                return handler(request)
            }
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
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default: return "Unknown"
        }
    }
}
