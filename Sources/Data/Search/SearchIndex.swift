import Foundation
import GRDB

public struct SearchHit: Equatable, Sendable, Identifiable {
    public let documentID: DocumentID
    public let pageID: PageID
    public let documentName: String
    public let snippet: String

    public var id: PageID { pageID }
}

public protocol SearchIndexProtocol: Sendable {
    func search(_ query: String, limit: Int) async throws -> [SearchHit]
}

/// Поиск по распознанному тексту.
///
/// Записи в индекс никто не делает вручную: он живёт триггерами на таблице
/// страниц. Ручное обновление означало бы два источника правды, которые
/// расходятся при первом же сбое.
public struct SearchIndex: SearchIndexProtocol {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func search(_ query: String, limit: Int) async throws -> [SearchHit] {
        // Запрос человека — это набор букв, а не выражение FTS5. Разбор
        // через FTS5Pattern превращает его в безопасный образец: кавычки
        // и служебные знаки не могут ни сломать поиск, ни изменить смысл.
        guard let pattern = FTS5Pattern(matchingAllPrefixesIn: query) else {
            return []
        }

        return try await database.writer.read { db in
            let sql = """
                SELECT
                    page.id AS pageId,
                    page.documentId AS documentId,
                    document.name AS documentName,
                    snippet(pageSearch, 0, '', '', '…', 12) AS snippet
                FROM pageSearch
                JOIN page ON page.rowid = pageSearch.rowid
                JOIN document ON document.id = page.documentId
                WHERE pageSearch MATCH ?
                ORDER BY rank
                LIMIT ?
                """

            let rows = try Row.fetchAll(db, sql: sql, arguments: [pattern, limit])

            return rows.compactMap { row -> SearchHit? in
                guard
                    let pageUUID = UUID(uuidString: row["pageId"]),
                    let documentUUID = UUID(uuidString: row["documentId"])
                else { return nil }

                return SearchHit(
                    documentID: DocumentID(documentUUID),
                    pageID: PageID(pageUUID),
                    documentName: row["documentName"],
                    snippet: row["snippet"]
                )
            }
        }
    }
}
