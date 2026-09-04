import Foundation
import Testing
@testable import Leaf

@Suite("Экран архива")
@MainActor
struct ArchiveModelTests {
    private func makeModel() throws -> (ArchiveModel, DocumentRepository) {
        let database = try AppDatabase.inMemory()
        let documents = DocumentRepository(database: database)
        let model = ArchiveModel(
            documents: documents,
            folders: FolderRepository(database: database),
            search: SearchIndex(database: database)
        )
        return (model, documents)
    }

    @Test("после загрузки документы разложены по группам")
    func documentsAreGroupedAfterLoading() async throws {
        let (model, documents) = try makeModel()
        try await documents.save(Document(name: "Свежий", pages: PageFactory.pages(count: 1)))

        await model.load()

        #expect(model.state == .ready)
        #expect(model.groups.count == 1)
        #expect(model.groups.first?.documents.first?.name == "Свежий")
    }

    @Test("пустой архив опознаётся явно — экрану есть что предложить")
    func emptyArchiveIsRecognizedExplicitly() async throws {
        let (model, _) = try makeModel()

        await model.load()

        #expect(model.state == .ready)
        #expect(model.isEmpty)
    }

    @Test("поиск отдаёт находки, а пустой запрос их убирает")
    func searchReturnsHitsAndEmptyQueryClearsThem() async throws {
        let (model, documents) = try makeModel()
        var page = PageFactory.page()
        page.recognizedText = "уникальноеслово"
        try await documents.save(Document(name: "Скан", pages: [page]))

        model.query = "уникальноеслово"
        await model.runSearch()
        #expect(model.hits.count == 1)

        model.query = "   "
        await model.runSearch()
        #expect(model.hits.isEmpty)
        #expect(model.isSearching == false)
    }

    @Test("удаление убирает документ из списка")
    func deletingRemovesDocumentFromList() async throws {
        let (model, documents) = try makeModel()
        let document = Document(name: "Лишний", pages: PageFactory.pages(count: 1))
        try await documents.save(document)
        await model.load()

        await model.delete(document.id)

        #expect(model.isEmpty)
    }

    @Test("папка создаётся и появляется в списке")
    func folderIsCreatedAndAppears() async throws {
        let (model, _) = try makeModel()

        await model.createFolder(named: "Работа")

        #expect(model.folders.count == 1)
        #expect(model.folders.first?.name == "Работа")
    }

    @Test("папка без имени не создаётся")
    func folderWithoutNameIsNotCreated() async throws {
        let (model, _) = try makeModel()

        await model.createFolder(named: "   ")

        #expect(model.folders.isEmpty)
    }

    @Test("отказ загрузки — это состояние с сообщением, а не пустой экран")
    func loadFailureIsAStateWithMessage() async throws {
        let model = ArchiveModel(
            documents: FailingDocumentRepository(),
            folders: FailingFolderRepository(),
            search: SearchIndex(database: try AppDatabase.inMemory())
        )

        await model.load()

        #expect(model.state == .failed(messageKey: "archive.error.load"))
    }
}

private struct FailingDocumentRepository: DocumentRepositoryProtocol {
    struct Failure: Error {}

    func save(_ document: Document) async throws { throw Failure() }
    func all(inFolder folderID: FolderID?) async throws -> [Document] { throw Failure() }
    func document(_ id: DocumentID) async throws -> Document? { throw Failure() }
    func delete(_ id: DocumentID) async throws { throw Failure() }
    func merge(_ ids: [DocumentID], into name: String) async throws -> Document { throw Failure() }
    func split(_ id: DocumentID, after index: Int, tailName: String) async throws -> (head: Document, tail: Document) {
        throw Failure()
    }
}

private struct FailingFolderRepository: FolderRepositoryProtocol {
    struct Failure: Error {}

    func save(_ folder: Folder) async throws { throw Failure() }
    func all(inParent parentID: FolderID?) async throws -> [Folder] { throw Failure() }
    func delete(_ id: FolderID) async throws { throw Failure() }
}

@Suite("Объединение документов из архива")
@MainActor
struct ArchiveMergeTests {
    private func makeModel() throws -> (ArchiveModel, DocumentRepository) {
        let database = try AppDatabase.inMemory()
        let documents = DocumentRepository(database: database)
        let model = ArchiveModel(
            documents: documents,
            folders: FolderRepository(database: database),
            search: SearchIndex(database: database)
        )
        return (model, documents)
    }

    @Test("два выделенных документа объединяются в один")
    func twoSelectedDocumentsBecomeOne() async throws {
        let (model, documents) = try makeModel()
        let first = Document(name: "Лицо", pages: PageFactory.pages(count: 2))
        let second = Document(name: "Оборот", pages: PageFactory.pages(count: 1))
        try await documents.save(first)
        try await documents.save(second)
        await model.load()

        model.toggleSelection(first.id)
        model.toggleSelection(second.id)
        await model.mergeSelection(into: "Целиком")

        let stored = try await documents.all(inFolder: nil)
        #expect(stored.count == 1)
        #expect(stored.first?.name == "Целиком")
        #expect(stored.first?.pages.count == 3)
        #expect(model.selection.isEmpty)
    }

    @Test("один документ объединять не с чем — объясняем, а не молчим")
    func mergingOneDocumentIsExplained() async throws {
        let (model, documents) = try makeModel()
        let only = Document(name: "Один", pages: PageFactory.pages(count: 1))
        try await documents.save(only)
        await model.load()
        model.toggleSelection(only.id)

        await model.mergeSelection(into: "Никак")

        #expect(model.state == .failed(messageKey: "archive.error.mergeOne"))
        #expect(try await documents.all(inFolder: nil).count == 1)
    }

    @Test("без имени берётся название первого документа, а не «объединённый»")
    func withoutNameTheFirstDocumentsNameIsUsed() async throws {
        let (model, documents) = try makeModel()
        let first = Document(name: "Договор аренды", pages: PageFactory.pages(count: 1))
        let second = Document(name: "Приложение", pages: PageFactory.pages(count: 1))
        try await documents.save(first)
        try await documents.save(second)
        await model.load()
        model.toggleSelection(first.id)
        model.toggleSelection(second.id)

        await model.mergeSelection(into: "   ")

        let stored = try await documents.all(inFolder: nil)
        #expect(stored.first?.name.isEmpty == false)
        #expect(stored.first?.name != "   ")
    }

    @Test("удаление выделенных убирает все выбранные документы")
    func deletingSelectionRemovesAllChosen() async throws {
        let (model, documents) = try makeModel()
        for index in 0..<3 {
            try await documents.save(Document(name: "Д\(index)", pages: PageFactory.pages(count: 1)))
        }
        await model.load()
        for document in model.groups.flatMap(\.documents).prefix(2) {
            model.toggleSelection(document.id)
        }

        await model.deleteSelection()

        #expect(try await documents.all(inFolder: nil).count == 1)
    }
}
