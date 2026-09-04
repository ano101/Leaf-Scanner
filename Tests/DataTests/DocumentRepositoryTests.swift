import Foundation
import Testing
@testable import Leaf

@Suite("Хранилище документов")
struct DocumentRepositoryTests {
    private func makeRepository() throws -> DocumentRepository {
        DocumentRepository(database: try AppDatabase.inMemory())
    }

    @Test("сохранённый документ читается обратно вместе со страницами")
    func savedDocumentComesBackWithItsPages() async throws {
        let repository = try makeRepository()
        let document = Document(name: "Договор", pages: PageFactory.pages(count: 2))

        try await repository.save(document)
        let stored = try await repository.all(inFolder: nil)

        #expect(stored.count == 1)
        #expect(stored.first?.name == "Договор")
        #expect(stored.first?.pages.count == 2)
    }

    @Test("страницы возвращаются в заданном порядке")
    func pagesComeBackInOrder() async throws {
        let repository = try makeRepository()
        let pages = PageFactory.pages(count: 3)
        try await repository.save(Document(name: "Паспорт", pages: pages))

        let stored = try await repository.all(inFolder: nil)

        #expect(stored.first?.pages.count == 3)
        #expect(stored.first?.pages.map(\.id) == pages.map(\.id))
    }

    @Test("повторное сохранение обновляет документ, а не создаёт второй")
    func savingTwiceUpdatesRatherThanDuplicates() async throws {
        let repository = try makeRepository()
        var document = Document(name: "Черновик", pages: PageFactory.pages(count: 1))
        try await repository.save(document)

        document.name = "Готово"
        try await repository.save(document)

        let stored = try await repository.all(inFolder: nil)
        #expect(stored.count == 1)
        #expect(stored.first?.name == "Готово")
    }

    @Test("удаление документа уносит его страницы")
    func deletingDocumentRemovesItsPages() async throws {
        let repository = try makeRepository()
        let document = Document(name: "Счёт", pages: PageFactory.pages(count: 2))
        try await repository.save(document)

        try await repository.delete(document.id)

        #expect(try await repository.all(inFolder: nil).isEmpty)
        #expect(try await repository.pageCount() == 0)
    }

    @Test("свойства страницы переживают запись и чтение")
    func pagePropertiesSurviveRoundTrip() async throws {
        let repository = try makeRepository()
        var page = PageFactory.page(order: 0, rotation: .left)
        page.look = .blackAndWhite
        page.perceptualHash = 0xF0F0_F0F0_F0F0_F0F0
        page.recognizedText = "Иванов Иван"
        page.redactions = [RedactionArea(rect: NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))]
        page.crop = .full

        try await repository.save(Document(name: "Скан", pages: [page]))
        let restored = try await repository.all(inFolder: nil).first?.pages.first

        #expect(restored?.rotation == .left)
        #expect(restored?.look == .blackAndWhite)
        #expect(restored?.perceptualHash == 0xF0F0_F0F0_F0F0_F0F0)
        #expect(restored?.recognizedText == "Иванов Иван")
        #expect(restored?.redactions.count == 1)
        #expect(restored?.crop == .full)
    }

    @Test("слияние собирает страницы в порядке указанных документов")
    func mergeCollectsPagesInGivenDocumentOrder() async throws {
        let repository = try makeRepository()
        let first = Document(name: "Лицо", pages: PageFactory.pages(count: 2))
        let second = Document(name: "Оборот", pages: PageFactory.pages(count: 1))
        try await repository.save(first)
        try await repository.save(second)

        let merged = try await repository.merge([second.id, first.id], into: "Целиком")

        #expect(merged.pages.count == 3)
        #expect(merged.pages.map(\.id) == second.pages.map(\.id) + first.pages.map(\.id))
        #expect(merged.pages.map(\.order) == [0, 1, 2])
    }

    @Test("слияние оставляет ровно один документ вместо исходных")
    func mergeReplacesSourcesWithSingleDocument() async throws {
        let repository = try makeRepository()
        let first = Document(name: "Один", pages: PageFactory.pages(count: 1))
        let second = Document(name: "Два", pages: PageFactory.pages(count: 1))
        try await repository.save(first)
        try await repository.save(second)

        _ = try await repository.merge([first.id, second.id], into: "Вместе")

        let stored = try await repository.all(inFolder: nil)
        #expect(stored.count == 1)
        #expect(stored.first?.name == "Вместе")
    }

    @Test("слияние с несуществующим документом не оставляет следов")
    func mergeWithMissingDocumentLeavesNothingBehind() async throws {
        let repository = try makeRepository()
        let existing = Document(name: "Есть", pages: PageFactory.pages(count: 1))
        try await repository.save(existing)

        await #expect(throws: RepositoryError.self) {
            _ = try await repository.merge([existing.id, DocumentID()], into: "Не выйдет")
        }

        let stored = try await repository.all(inFolder: nil)
        #expect(stored.count == 1)
        #expect(stored.first?.name == "Есть")
        #expect(try await repository.pageCount() == 1)
    }

    @Test("разделение даёт два документа с сохранённым порядком страниц")
    func splitGivesTwoDocumentsKeepingPageOrder() async throws {
        let repository = try makeRepository()
        let pages = PageFactory.pages(count: 4)
        let document = Document(name: "Пачка", pages: pages)
        try await repository.save(document)

        let (head, tail) = try await repository.split(document.id, after: 1, tailName: "Хвост")

        #expect(head.pages.map(\.id) == [pages[0].id, pages[1].id])
        #expect(tail.pages.map(\.id) == [pages[2].id, pages[3].id])
        #expect(head.pages.map(\.order) == [0, 1])
        #expect(tail.pages.map(\.order) == [0, 1])
    }

    @Test("после разделения в архиве два документа вместо одного")
    func afterSplitArchiveHoldsTwoDocuments() async throws {
        let repository = try makeRepository()
        let document = Document(name: "Пачка", pages: PageFactory.pages(count: 3))
        try await repository.save(document)

        _ = try await repository.split(document.id, after: 0, tailName: "Хвост")

        #expect(try await repository.all(inFolder: nil).count == 2)
        #expect(try await repository.pageCount() == 3)
    }

    @Test("разделение по краю списка отклоняется, а не создаёт пустой документ")
    func splitAtTheEdgeIsRejected() async throws {
        let repository = try makeRepository()
        let document = Document(name: "Пачка", pages: PageFactory.pages(count: 2))
        try await repository.save(document)

        await #expect(throws: RepositoryError.self) {
            _ = try await repository.split(document.id, after: 1, tailName: "Хвост")
        }
        #expect(try await repository.all(inFolder: nil).count == 1)
    }

    @Test("документы разложены по папкам")
    func documentsAreFilteredByFolder() async throws {
        let repository = try makeRepository()
        let folders = FolderRepository(database: repository.database)
        let folder = Folder(name: "Работа")
        try await folders.save(folder)

        try await repository.save(Document(name: "В папке", folderID: folder.id))
        try await repository.save(Document(name: "Снаружи"))

        let inFolder = try await repository.all(inFolder: folder.id)
        let outside = try await repository.all(inFolder: nil)

        #expect(inFolder.count == 1)
        #expect(inFolder.first?.name == "В папке")
        #expect(outside.count == 1)
        #expect(outside.first?.name == "Снаружи")
    }
}
