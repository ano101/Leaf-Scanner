import Foundation
import GRDB

struct FolderRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "folder"

    var id: String
    var name: String
    var parentId: String?
    var createdAt: Date

    init(folder: Folder) {
        self.id = folder.id.raw.uuidString
        self.name = folder.name
        self.parentId = folder.parentID?.raw.uuidString
        self.createdAt = folder.createdAt
    }

    func toFolder() throws -> Folder {
        guard let uuid = UUID(uuidString: id) else {
            throw RepositoryError.corruptedRecord(table: Self.databaseTableName, id: id)
        }

        return Folder(
            id: FolderID(uuid),
            name: name,
            parentID: parentId.flatMap { UUID(uuidString: $0) }.map { FolderID($0) },
            createdAt: createdAt
        )
    }
}
