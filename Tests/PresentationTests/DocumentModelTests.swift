import Foundation
import Testing
@testable import Leaf

@Suite("Экран документа")
@MainActor
struct DocumentModelTests {
    private func makeModel(pageCount: Int = 3) async throws -> (DocumentModel, DocumentRepository) {
        let repository = DocumentRepository(database: try AppDatabase.inMemory())
        let document = Document(name: "Договор", pages: PageFactory.pages(count: pageCount))
        try await repository.save(document)
        return (DocumentModel(document: document, documents: repository), repository)
    }

    @Test("поворот применяется и сохраняется")
    func rotationIsAppliedAndStored() async throws {
        let (model, repository) = try await makeModel()
        let pageID = try #require(model.pages.first?.id)

        await model.rotateRight(pageID)

        #expect(model.pages.first?.rotation == .right)
        let stored = try #require(try await repository.document(model.document.id))
        #expect(stored.pages.first?.rotation == .right)
    }

    @Test("поворот всех страниц не пропускает ни одной")
    func rotatingAllSkipsNothing() async throws {
        let (model, _) = try await makeModel()

        await model.rotateAllRight()

        #expect(model.pages.allSatisfy { $0.rotation == .right })
    }

    @Test("перестановка меняет порядок и оставляет нумерацию подряд")
    func reorderingKeepsNumbersConsecutive() async throws {
        let (model, _) = try await makeModel()
        let first = try #require(model.pages.first?.id)

        await model.move(from: 0, to: 2)

        #expect(model.pages.map(\.order) == [0, 1, 2])
        #expect(model.pages.last?.id == first)
    }

    @Test("удаление страницы уменьшает документ")
    func deletingPageShrinksDocument() async throws {
        let (model, _) = try await makeModel()
        let pageID = try #require(model.pages.first?.id)

        await model.deletePage(pageID)

        #expect(model.pages.count == 2)
        #expect(model.pages.map(\.order) == [0, 1])
    }

    @Test("последняя страница не удаляется — вместо неё объяснение")
    func lastPageIsKeptWithAnExplanation() async throws {
        let (model, _) = try await makeModel(pageCount: 1)
        let pageID = try #require(model.pages.first?.id)

        await model.deletePage(pageID)

        #expect(model.pages.count == 1)
        #expect(model.state == .failed(messageKey: "document.error.lastPage"))
    }

    @Test("замазка добавляется и снимается")
    func redactionIsAddedAndCleared() async throws {
        let (model, _) = try await makeModel()
        let pageID = try #require(model.pages.first?.id)
        let area = RedactionArea(rect: NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.05))

        await model.addRedaction(area, to: pageID)
        #expect(model.pages.first?.redactions.count == 1)

        await model.removeRedactions(from: pageID)
        #expect(model.pages.first?.redactions.isEmpty == true)
    }

    @Test("переименование пустой строкой не стирает название")
    func renamingWithBlankKeepsTheName() async throws {
        let (model, _) = try await makeModel()

        await model.rename(to: "   ")

        #expect(model.document.name == "Договор")
    }

    @Test("разделение отдаёт второй документ и укорачивает первый")
    func splitReturnsTailAndShortensHead() async throws {
        let (model, _) = try await makeModel()

        let tail = await model.split(after: 0, tailName: "Хвост")

        #expect(model.pages.count == 1)
        #expect(tail?.pages.count == 2)
    }

    @Test("разделение по краю объясняется, а не молчит")
    func splitAtTheEdgeExplainsItself() async throws {
        let (model, _) = try await makeModel()

        let tail = await model.split(after: 2, tailName: "Хвост")

        #expect(tail == nil)
        #expect(model.state == .failed(messageKey: "document.error.splitEdge"))
        #expect(model.pages.count == 3)
    }
}
