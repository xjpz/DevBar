import Foundation
import SwiftData

@Model
final class IOSAPIRecord {
    var id: UUID
    var title: String
    var url: String
    var method: String = "GET"
    var requestType: String = "Page"
    var headers: String = ""
    var body: String = ""
    var provider: String?
    var tags: [String]
    var notes: String
    var createdAt: Date
    var lastOpenedAt: Date
    var isFavorite: Bool

    init(
        id: UUID = UUID(),
        title: String,
        url: String,
        method: String = "GET",
        requestType: String = "Page",
        headers: String = "",
        body: String = "",
        provider: String? = nil,
        tags: [String] = [],
        notes: String = "",
        createdAt: Date = .now,
        lastOpenedAt: Date = .now,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.method = method
        self.requestType = requestType
        self.headers = headers
        self.body = body
        self.provider = provider
        self.tags = tags
        self.notes = notes
        self.createdAt = createdAt
        self.lastOpenedAt = lastOpenedAt
        self.isFavorite = isFavorite
    }
}
