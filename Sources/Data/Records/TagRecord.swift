import Foundation
import GRDB

struct TagRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "tag"

    var id: String
    var name: String
    var colorKey: String

    init(tag: Tag) {
        self.id = tag.id.raw.uuidString
        self.name = tag.name
        self.colorKey = tag.colorKey
    }

    func toTag() throws -> Tag {
        guard let uuid = UUID(uuidString: id) else {
            throw RepositoryError.corruptedRecord(table: Self.databaseTableName, id: id)
        }
        return Tag(id: TagID(uuid), name: name, colorKey: colorKey)
    }
}

struct DocumentTagRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "documentTag"

    var documentId: String
    var tagId: String
}
