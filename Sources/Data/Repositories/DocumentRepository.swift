import Foundation
import GRDB

public protocol DocumentRepositoryProtocol: Sendable {
    func save(_ document: Document) async throws
    func all(inFolder folderID: FolderID?) async throws -> [Document]
    func document(_ id: DocumentID) async throws -> Document?
    func delete(_ id: DocumentID) async throws
    func merge(_ ids: [DocumentID], into name: String) async throws -> Document
    func split(_ id: DocumentID, after index: Int, tailName: String) async throws -> (head: Document, tail: Document)
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

    /// Список архива собирается тремя запросами независимо от числа
    /// документов: сами документы, все их страницы и все метки.
    ///
    /// Запрос страниц на каждый документ превращал бы открытие архива
    /// из тысячи строк в две тысячи обращений к базе. Замер показывал
    /// сто сорок миллисекунд вместо обещанных ста — человек это замечает.
    public func all(inFolder folderID: FolderID?) async throws -> [Document] {
        try await database.writer.read { db in
            let records = try DocumentRecord
                .filter(Column("folderId") == folderID?.raw.uuidString)
                .order(Column("updatedAt").desc)
                .fetchAll(db)

            guard records.isEmpty == false else { return [] }

            // Условие повторяется подзапросом, а не списком идентификаторов:
            // тысяча параметров упёрлась бы в предел SQLite.
            let scope = folderID == nil
                ? "SELECT id FROM document WHERE folderId IS NULL"
                : "SELECT id FROM document WHERE folderId = ?"
            let arguments: StatementArguments = folderID
                .map { [$0.raw.uuidString] }
                ?? []

            let pageRows = try PageRecord.fetchAll(
                db,
                sql: "SELECT * FROM page WHERE documentId IN (\(scope)) ORDER BY ordinal",
                arguments: arguments
            )
            let tagRows = try DocumentTagRecord.fetchAll(
                db,
                sql: "SELECT * FROM documentTag WHERE documentId IN (\(scope))",
                arguments: arguments
            )

            var pagesByDocument: [String: [Page]] = [:]
            for row in pageRows {
                pagesByDocument[row.documentId, default: []].append(try row.toPage())
            }

            var tagsByDocument: [String: [TagID]] = [:]
            for row in tagRows {
                guard let uuid = UUID(uuidString: row.tagId) else { continue }
                tagsByDocument[row.documentId, default: []].append(TagID(uuid))
            }

            return try records.map { record in
                try record.toDocument(
                    pages: pagesByDocument[record.id] ?? [],
                    tagIDs: tagsByDocument[record.id] ?? []
                )
            }
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

    /// Разделение документа надвое. Как и слияние, идёт одной транзакцией:
    /// половина страниц, оставшаяся без документа, была бы потерей данных.
    public func split(
        _ id: DocumentID,
        after index: Int,
        tailName: String
    ) async throws -> (head: Document, tail: Document) {
        guard var document = try await self.document(id) else {
            throw RepositoryError.documentNotFound(id)
        }

        // Разрез по краю оставил бы один из документов пустым. Пустой документ
        // в архиве — это строка, которую человек откроет и не поймёт, зачем она.
        guard index >= 0, index < document.pages.count - 1 else {
            throw RepositoryError.splitWouldLeaveEmptyDocument
        }

        let ordered = PageOrdering.sorted(document.pages)
        let headPages = PageOrdering.renumbered(Array(ordered[...index]))
        let tailPages = PageOrdering.renumbered(Array(ordered[(index + 1)...]))

        document.pages = headPages
        document.updatedAt = Date()

        var tail = Document(name: tailName, pages: tailPages)
        tail.folderID = document.folderID
        tail.tagIDs = document.tagIDs

        let headRecord = DocumentRecord(document: document)
        let tailRecord = DocumentRecord(document: tail)
        let headPageRecords = try headPages.map { try PageRecord(page: $0, documentId: document.id) }
        let tailPageRecords = try tailPages.map { try PageRecord(page: $0, documentId: tail.id) }

        try await database.writer.write { db in
            try headRecord.save(db)
            try tailRecord.insert(db)

            // Страницы хвоста меняют владельца, поэтому старые записи
            // снимаются раньше вставки новых: идентификаторы те же.
            try PageRecord
                .filter(Column("documentId") == headRecord.id)
                .deleteAll(db)
            for record in headPageRecords + tailPageRecords {
                try record.insert(db)
            }
        }

        return (document, tail)
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
