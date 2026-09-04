import CoreGraphics
import Foundation
import Testing
@testable import Leaf

@Suite("Фоновое распознавание")
struct TextRecognitionWorkerTests {
    private struct Context {
        let worker: TextRecognitionWorker
        let documents: DocumentRepository
        let search: SearchIndex
        let importer: ScanImporter
        let root: URL
    }

    private func makeContext() throws -> Context {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("leaf-ocr-\(UUID().uuidString)")
        let store = try PageStore(root: root)
        let database = try AppDatabase.inMemory()
        let documents = DocumentRepository(database: database)

        return Context(
            worker: TextRecognitionWorker(
                images: store,
                recognizer: TextRecognizer(),
                documents: documents
            ),
            documents: documents,
            search: SearchIndex(database: database),
            importer: ScanImporter(store: store),
            root: root
        )
    }

    @Test("распознанный текст доходит до документа и до поиска")
    func recognizedTextReachesDocumentAndSearch() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.root) }

        let pages = try await context.importer.makePages(from: [ImageFactory.text("ДОГОВОР")])
        let document = Document(name: "Скан", pages: pages)
        try await context.documents.save(document)

        try await context.worker.process(documentID: document.id)

        let stored = try #require(try await context.documents.document(document.id))
        #expect(stored.pages.first?.recognizedText?.isEmpty == false)
        #expect(try await context.search.search("договор", limit: 10).isEmpty == false)
    }

    @Test("страница с уже распознанным текстом заново не обрабатывается")
    func alreadyRecognizedPageIsNotProcessedAgain() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.root) }

        var pages = try await context.importer.makePages(from: [ImageFactory.text("СЧЁТ")])
        pages[0].recognizedText = "уже разобрано"
        let document = Document(name: "Скан", pages: pages)
        try await context.documents.save(document)

        try await context.worker.process(documentID: document.id)

        let stored = try #require(try await context.documents.document(document.id))
        #expect(stored.pages.first?.recognizedText == "уже разобрано")
    }

    @Test("нераспознаваемая страница не ломает документ")
    func unreadablePageDoesNotBreakTheDocument() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.root) }

        let pages = try await context.importer.makePages(from: [
            ImageFactory.solid(width: 400, height: 300, gray: 1.0),
        ])
        let document = Document(name: "Пустой лист", pages: pages)
        try await context.documents.save(document)

        try await context.worker.process(documentID: document.id)

        let stored = try #require(try await context.documents.document(document.id))
        #expect(stored.pages.count == 1)
        #expect(stored.name == "Пустой лист")
    }

    @Test("отсутствующий документ не роняет работника")
    func missingDocumentDoesNotCrashTheWorker() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.root) }

        try await context.worker.process(documentID: DocumentID())
    }
}

@Suite("Уточнение имени после распознавания")
struct DocumentNamingTests {
    private func makeContext() throws -> (TextRecognitionWorker, DocumentRepository, ScanImporter, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("leaf-naming-\(UUID().uuidString)")
        let store = try PageStore(root: root)
        let database = try AppDatabase.inMemory()
        let documents = DocumentRepository(database: database)

        return (
            TextRecognitionWorker(images: store, recognizer: TextRecognizer(), documents: documents),
            documents,
            ScanImporter(store: store),
            root
        )
    }

    @Test("имя-дата уточняется заголовком, найденным на листе")
    func dateNameIsRefinedByTheHeadingOnTheSheet() async throws {
        let (worker, documents, importer, root) = try makeContext()
        defer { try? FileManager.default.removeItem(at: root) }

        let pages = try await importer.makePages(from: [ImageFactory.text("ДОГОВОР")])
        let document = Document(
            name: ScanImporter.suggestedName(from: nil, date: Date()),
            pages: pages
        )
        try await documents.save(document)

        try await worker.process(documentID: document.id)

        let stored = try #require(try await documents.document(document.id))
        #expect(stored.name.uppercased().contains("ДОГОВОР"))
    }

    @Test("имя, заданное человеком, распознавание не трогает")
    func nameGivenByThePersonIsNeverTouched() async throws {
        let (worker, documents, importer, root) = try makeContext()
        defer { try? FileManager.default.removeItem(at: root) }

        let pages = try await importer.makePages(from: [ImageFactory.text("ДОГОВОР")])
        let document = Document(name: "Моё название", pages: pages, isNameAutomatic: false)
        try await documents.save(document)

        try await worker.process(documentID: document.id)

        let stored = try #require(try await documents.document(document.id))
        #expect(stored.name == "Моё название")
    }

    @Test("признак автоматического имени переживает запись и чтение")
    func automaticNameFlagSurvivesRoundTrip() async throws {
        let (_, documents, _, root) = try makeContext()
        defer { try? FileManager.default.removeItem(at: root) }

        try await documents.save(Document(name: "Ручное", isNameAutomatic: false))
        try await documents.save(Document(name: "Само", isNameAutomatic: true))

        let stored = try await documents.all(inFolder: nil)
        #expect(stored.count == 2)
        #expect(stored.first { $0.name == "Ручное" }?.isNameAutomatic == false)
        #expect(stored.first { $0.name == "Само" }?.isNameAutomatic == true)
    }
}

@Suite("Срок действия в документе")
struct DocumentExpiryTests {
    @Test("признак срока переживает запись и чтение")
    func expiryDateSurvivesRoundTrip() async throws {
        let repository = DocumentRepository(database: try AppDatabase.inMemory())
        let expiry = Date(timeIntervalSince1970: 1_900_000_000)

        try await repository.save(Document(name: "Паспорт", expiresAt: expiry))
        let stored = try await repository.all(inFolder: nil).first

        #expect(stored?.expiresAt != nil)
        #expect(abs((stored?.expiresAt ?? .distantPast).timeIntervalSince(expiry)) < 1)
    }

    @Test("документ без срока хранится без него, а не с выдуманной датой")
    func documentWithoutExpiryStaysWithout() async throws {
        let repository = DocumentRepository(database: try AppDatabase.inMemory())
        try await repository.save(Document(name: "Договор"))

        #expect(try await repository.all(inFolder: nil).first?.expiresAt == nil)
    }

    @Test("срок ищется по всему документу, а не только на первой странице")
    func expiryIsSearchedAcrossTheWholeDocument() {
        // В паспорте срок на развороте, в полисе — в конце. Разбор только
        // первой страницы пропустил бы оба случая.
        let pages = ["ПАСПОРТ", "Российская Федерация", "Действителен до 03.03.2030"]
        let whole = pages.joined(separator: "\n")

        #expect(ExpiryDetector().detect(in: whole) != nil)
        #expect(ExpiryDetector().detect(in: pages[0]) == nil)
    }
}
