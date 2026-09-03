import Foundation
import GRDB

public protocol DocumentRepositoryProtocol: Sendable {
    func save(_ document: Document) async throws
    func all(inFolder folderID: FolderID?) async throws -> [Document]
    func document(_ id: DocumentID) async throws -> Document?
    func delete(_ id: DocumentID) async throws
    func merge(_ ids: [DocumentID], into name: String) async throws -> Document
}

public struct DocumentRepository: DocumentRepositoryProtocol {
    let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func save(_ document: Document) async throws {
        let record = DocumentRecord(document: document)
        let pages = try PageOrdering.renumbered(document.pages)
            .map { try PageRecord(page: $0, documentId: document.id) }
        let tagLinks = document.tagIDs.map {
            DocumentTagRecord(documentId: document.id.raw.uuidString, tagId: $0.raw.uuidString)
        }

        try await database.writer.write { db in
            try record.save(db)

            // Страницы переписываются целиком: порядок и состав меняются
            // вместе, и частичное обновление оставило бы дыры в нумерации.
            try PageRecord
                .filter(Column("documentId") == record.id)
                .deleteAll(db)
            for page in pages {
                try page.insert(db)
            }

            try DocumentTagRecord
                .filter(Column("documentId") == record.id)
                .deleteAll(db)
            for link in tagLinks {
                try link.insert(db)
            }
        }
    }

    public func all(inFolder folderID: FolderID?) async throws -> [Document] {
        try await database.writer.read { db in
            let request = DocumentRecord
                .filter(Column("folderId") == folderID?.raw.uuidString)
                .order(Column("updatedAt").desc)
            let records = try request.fetchAll(db)

            return try records.map { try Self.assemble($0, in: db) }
        }
    }

    public func document(_ id: DocumentID) async throws -> Document? {
        try await database.writer.read { db in
            guard let record = try DocumentRecord.fetchOne(db, key: id.raw.uuidString) else {
                return nil
            }
            return try Self.assemble(record, in: db)
        }
    }

    public func delete(_ id: DocumentID) async throws {
        try await database.writer.write { db in
            _ = try DocumentRecord.deleteOne(db, key: id.raw.uuidString)
        }
    }

    /// Слияние идёт одной транзакцией: либо появляется новый документ и
    /// исчезают исходные, либо не меняется ничего. Промежуточное состояние,
    /// в котором страницы уже перенесены, а исходники ещё целы, означало бы
    /// дубликаты в архиве.
    public func merge(_ ids: [DocumentID], into name: String) async throws -> Document {
        guard ids.isEmpty == false else { throw RepositoryError.nothingToMerge }

        let merged = try await database.writer.write { db -> Document in
            var collected: [Page] = []

            for id in ids {
                guard let record = try DocumentRecord.fetchOne(db, key: id.raw.uuidString) else {
                    throw RepositoryError.documentNotFound(id)
                }
                collected.append(contentsOf: try Self.pages(of: record.id, in: db))
            }

            let folderId = try DocumentRecord
                .fetchOne(db, key: ids[0].raw.uuidString)?
                .folderId

            var document = Document(name: name, pages: PageOrdering.renumbered(collected))
            document.folderID = folderId.flatMap { UUID(uuidString: $0) }.map { FolderID($0) }

            // Исходники снимаются раньше вставки: страницы сохраняют свои
            // идентификаторы, и пока старые записи живы, новые в таблицу
            // не помещаются.
            for id in ids {
                _ = try DocumentRecord.deleteOne(db, key: id.raw.uuidString)
            }

            try DocumentRecord(document: document).insert(db)
            for page in document.pages {
                try PageRecord(page: page, documentId: document.id).insert(db)
            }

            return document
        }

        return merged
    }

    /// Служебный счётчик для проверки каскадного удаления в тестах.
    func pageCount() async throws -> Int {
        try await database.writer.read { db in
            try PageRecord.fetchCount(db)
        }
    }

    private static func assemble(_ record: DocumentRecord, in db: Database) throws -> Document {
        let pages = try pages(of: record.id, in: db)
        let tagIDs = try DocumentTagRecord
            .filter(Column("documentId") == record.id)
            .fetchAll(db)
            .compactMap { UUID(uuidString: $0.tagId) }
            .map { TagID($0) }

        return try record.toDocument(pages: pages, tagIDs: tagIDs)
    }

    private static func pages(of documentId: String, in db: Database) throws -> [Page] {
        try PageRecord
            .filter(Column("documentId") == documentId)
            .order(Column("ordinal"))
            .fetchAll(db)
            .map { try $0.toPage() }
    }
}
