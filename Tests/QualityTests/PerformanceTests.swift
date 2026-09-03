import Foundation
import Testing
@testable import Leaf

/// Скорость заявлена в спеке числами, значит числами и проверяется.
/// «Кажется быстрым» — не результат.
@Suite("Скорость архива", .serialized)
struct PerformanceTests {
    private static let documentCount = 1000

    private func filledDatabase() async throws -> AppDatabase {
        let database = try AppDatabase.inMemory()
        let repository = DocumentRepository(database: database)

        for index in 0..<Self.documentCount {
            var page = PageFactory.page()
            page.recognizedText = "Договор номер \(index) от 12.03.2026 на поставку оборудования"
            try await repository.save(Document(name: "Документ \(index)", pages: [page]))
        }

        return database
    }

    private func seconds(_ work: () async throws -> Void) async rethrows -> Double {
        let clock = ContinuousClock()
        let elapsed = try await clock.measure { try await work() }
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    @Test("архив из тысячи документов открывается быстрее ста миллисекунд")
    func archiveOfThousandOpensUnderHundredMilliseconds() async throws {
        let repository = DocumentRepository(database: try await filledDatabase())

        // Первое обращение прогревает соединение; замеряется установившееся.
        _ = try await repository.all(inFolder: nil)

        let elapsed = try await seconds {
            let documents = try await repository.all(inFolder: nil)
            #expect(documents.count == Self.documentCount)
        }

        #expect(elapsed < 0.1, "архив открывался \(Int(elapsed * 1000)) мс")
    }

    @Test("поиск по тексту отвечает быстрее пятидесяти миллисекунд")
    func searchAnswersUnderFiftyMilliseconds() async throws {
        let database = try await filledDatabase()
        let search = SearchIndex(database: database)
        _ = try await search.search("договор", limit: 50)

        let elapsed = try await seconds {
            let hits = try await search.search("оборудования", limit: 50)
            #expect(hits.isEmpty == false)
        }

        #expect(elapsed < 0.05, "поиск отвечал \(Int(elapsed * 1000)) мс")
    }

    @Test("группировка тысячи документов не заметна на глаз")
    func groupingThousandDocumentsIsImperceptible() async throws {
        let documents = try await DocumentRepository(database: try await filledDatabase())
            .all(inFolder: nil)
        let now = Date()

        let elapsed = try await seconds {
            let groups = DocumentGrouping.group(documents, now: now)
            #expect(groups.isEmpty == false)
        }

        #expect(elapsed < 0.05, "группировка заняла \(Int(elapsed * 1000)) мс")
    }

    @Test("список берёт миниатюры, а не оригиналы страниц")
    func listReadsThumbnailsNotOriginals() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("leaf-speed-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try PageStore(root: root)
        let loader = ThumbnailLoader(store: store)
        let id = PageID()
        _ = try await store.storeOriginal(ImageFactory.gradient(width: 2400, height: 3200), for: id)

        let thumbnail = try #require(await loader.thumbnail(for: id))

        // Оригинал в четыре с лишним раза длиннее: если бы список открывал
        // его, прокрутка архива читала бы с диска мегабайты на каждую строку.
        #expect(max(thumbnail.width, thumbnail.height) <= PageStore.thumbnailSide)
    }

    @Test("повторный показ строки берёт миниатюру из памяти")
    func repeatedRowShowTakesThumbnailFromMemory() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("leaf-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try PageStore(root: root)
        let loader = ThumbnailLoader(store: store)
        let id = PageID()
        _ = try await store.storeOriginal(ImageFactory.gradient(width: 2000, height: 2600), for: id)

        _ = await loader.thumbnail(for: id)
        // Файл убран: если бы кэша не было, второе обращение вернуло бы пустоту.
        try await store.remove(id)

        #expect(await loader.thumbnail(for: id) != nil)
    }
}
