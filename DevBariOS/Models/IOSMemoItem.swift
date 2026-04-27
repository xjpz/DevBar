import Foundation
import SwiftData

@Model
final class IOSMemoItem {
    var id: UUID
    var title: String
    var content: String
    var encryptedData: Data?
    var isEncrypted: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "",
        content: String = "",
        encryptedData: Data? = nil,
        isEncrypted: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.encryptedData = encryptedData
        self.isEncrypted = isEncrypted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
