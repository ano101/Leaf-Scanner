import Foundation
import GRDB

struct DocumentRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "document"

    var id: String
    var name: String
    var folderId: String?
    var createdAt: Date
    var updatedAt: Date
    var isNameAutomatic: Bool
    var expiresAt: Date?

    init(document: Document) {
        self.id = document.id.raw.uuidString
        self.name = document.name
        self.folderId = document.folderID?.raw.uuidString
        self.createdAt = document.createdAt
        self.updatedAt = document.updatedAt
        self.isNameAutomatic = document.isNameAutomatic
        self.expiresAt = document.expiresAt
    }

    func toDocument(pages: [Page], tagIDs: [TagID]) throws -> Document {
        guard let uuid = UUID(uuidString: id) else {
            throw RepositoryError.corruptedRecord(table: Self.databaseTableName, id: id)
        }

        return Document(
            id: DocumentID(uuid),
            name: name,
            folderID: folderId.flatMap { UUID(uuidString: $0) }.map { FolderID($0) },
            tagIDs: tagIDs,
            createdAt: createdAt,
            updatedAt: updatedAt,
            pages: pages,
            isNameAutomatic: isNameAutomatic,
            expiresAt: expiresAt
        )
    }
}
