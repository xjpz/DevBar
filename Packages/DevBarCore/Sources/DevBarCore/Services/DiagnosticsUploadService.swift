import Foundation

public enum DiagnosticsUploadServiceError: Error, Equatable {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case serverError(String)
}

public struct DiagnosticsUploadResult: Codable, Equatable, Sendable {
    public let accepted: Int
    public let rejected: Int
    public let duplicate: Int

    public init(accepted: Int, rejected: Int, duplicate: Int) {
        self.accepted = accepted
        self.rejected = rejected
        self.duplicate = duplicate
    }

    public static let empty = DiagnosticsUploadResult(accepted: 0, rejected: 0, duplicate: 0)
}

public final class DiagnosticsUploadService: Sendable {
    public static let shared = DiagnosticsUploadService()

    private let baseURL: URL
    private let session: URLSession
    private let store: DiagnosticLogStore

    public init(
        baseURL: URL = URL(string: DevBarCoreConstants.DeviceRelay.baseURL)!,
        session: URLSession = .shared,
        store: DiagnosticLogStore = DiagnosticLogStore(directoryURL: DiagnosticLogStore.defaultDirectoryURL())
    ) {
        self.baseURL = baseURL
        self.session = session
        self.store = store
    }

    @discardableResult
    public func flush(
        deviceToken: String,
        limit: Int = 100,
        maxBytes: Int = 256 * 1_024
    ) async throws -> DiagnosticsUploadResult {
        let events = try store.loadBatch(limit: limit, maxBytes: maxBytes)
        guard !events.isEmpty else { return .empty }

        guard let endpoint = URL(string: DevBarCoreConstants.Diagnostics.logsPath, relativeTo: baseURL)?.absoluteURL else {
            throw DiagnosticsUploadServiceError.invalidURL
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(DiagnosticsUploadRequest(events: events))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DiagnosticsUploadServiceError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw DiagnosticsUploadServiceError.httpError(httpResponse.statusCode)
        }

        let envelope: DiagnosticsUploadEnvelope
        do {
            envelope = try JSONDecoder().decode(DiagnosticsUploadEnvelope.self, from: data)
        } catch {
            throw DiagnosticsUploadServiceError.invalidResponse
        }
        guard envelope.success != false else {
            throw DiagnosticsUploadServiceError.serverError(envelope.message ?? String(envelope.code ?? 0))
        }

        let result = envelope.data ?? .empty
        try store.remove(eventIDs: Set(events.map(\.eventId)))
        return result
    }
}

private struct DiagnosticsUploadRequest: Encodable {
    let events: [DiagnosticLogEvent]
}

private struct DiagnosticsUploadEnvelope: Decodable {
    let success: Bool?
    let code: Int?
    let message: String?
    let data: DiagnosticsUploadResult?

    private enum CodingKeys: String, CodingKey {
        case success
        case code
        case message = "msg"
        case data
    }
}
