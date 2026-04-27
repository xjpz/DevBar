import Foundation
import SwiftData

@Model
final class IOSWebHistoryRecord {
    var id: UUID
    var title: String
    var url: String
    var visitedAt: Date
    var visitCount: Int

    init(
        id: UUID = UUID(),
        title: String,
        url: String,
        visitedAt: Date = .now,
        visitCount: Int = 1
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.visitedAt = visitedAt
        self.visitCount = visitCount
    }
}
