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

@Suite("Выделение страниц")
@MainActor
struct PageSelectionTests {
    private func makeModel(pageCount: Int = 3) async throws -> DocumentModel {
        let repository = DocumentRepository(database: try AppDatabase.inMemory())
        let document = Document(name: "Пачка", pages: PageFactory.pages(count: pageCount))
        try await repository.save(document)
        return DocumentModel(document: document, documents: repository)
    }

    @Test("нажатие добавляет и убирает страницу из выделения")
    func tapAddsAndRemovesPage() async throws {
        let model = try await makeModel()
        let id = try #require(model.pages.first?.id)

        model.toggleSelection(id)
        #expect(model.selection == [id])

        model.toggleSelection(id)
        #expect(model.selection.isEmpty)
    }

    @Test("поворот применяется только к выделенным страницам")
    func rotationTouchesOnlySelectedPages() async throws {
        let model = try await makeModel()
        let first = try #require(model.pages.first?.id)
        model.toggleSelection(first)

        await model.rotateSelectionRight()

        #expect(model.pages.first?.rotation == .right)
        #expect(model.pages.dropFirst().allSatisfy { $0.rotation == Rotation.none })
    }

    @Test("удаление выделенных убирает ровно их")
    func deletingSelectionRemovesExactlyThose() async throws {
        let model = try await makeModel()
        let first = try #require(model.pages.first?.id)
        let second = try #require(model.pages.dropFirst().first?.id)
        model.toggleSelection(first)
        model.toggleSelection(second)

        await model.deleteSelection()

        #expect(model.pages.count == 1)
        #expect(model.selection.isEmpty)
    }

    @Test("удалить все страницы разом нельзя — вместо этого объяснение")
    func deletingEveryPageIsRefusedWithAnExplanation() async throws {
        let model = try await makeModel(pageCount: 2)
        for page in model.pages { model.toggleSelection(page.id) }

        await model.deleteSelection()

        #expect(model.pages.count == 2)
        #expect(model.state == .failed(messageKey: "document.error.lastPage"))
    }

    @Test("поворот влево обратен повороту вправо")
    func leftRotationUndoesRight() async throws {
        let model = try await makeModel()
        let id = try #require(model.pages.first?.id)

        await model.rotateRight(id)
        await model.rotateLeft(id)

        // Явный тип обязателен: «.none» без него Swift читает как «пусто»,
        // и проверка сравнивает поворот с отсутствием значения.
        #expect(model.pages.first?.rotation == Rotation.none)
    }

    @Test("вид применяется ко всем страницам разом")
    func lookAppliesToEveryPage() async throws {
        let model = try await makeModel()

        await model.setLookForAllPages(.blackAndWhite)

        #expect(model.pages.allSatisfy { $0.look == .blackAndWhite })
    }
}

@Suite("Откат правок")
@MainActor
struct DocumentUndoTests {
    private func makeModel(pageCount: Int = 2) async throws -> (DocumentModel, DocumentRepository) {
        let repository = DocumentRepository(database: try AppDatabase.inMemory())
        let document = Document(name: "Договор", pages: PageFactory.pages(count: pageCount))
        try await repository.save(document)
        return (DocumentModel(document: document, documents: repository), repository)
    }

    @Test("до первой правки откатывать нечего")
    func nothingToUndoBeforeTheFirstChange() async throws {
        let (model, _) = try await makeModel()

        #expect(model.canUndo == false)
        await model.undo()
        #expect(model.pages.allSatisfy { $0.rotation == Rotation.none })
    }

    @Test("откат возвращает страницу в прежнее положение")
    func undoBringsThePageBack() async throws {
        let (model, repository) = try await makeModel()
        let id = try #require(model.pages.first?.id)
        await model.rotateRight(id)
        #expect(model.canUndo)

        await model.undo()

        #expect(model.pages.first?.rotation == Rotation.none)
        let stored = try #require(try await repository.document(model.document.id))
        #expect(stored.pages.first?.rotation == Rotation.none)
    }

    @Test("откат снимает правки по одной, а не все разом")
    func undoStepsBackOneChangeAtATime() async throws {
        let (model, _) = try await makeModel()
        let id = try #require(model.pages.first?.id)
        await model.rotateRight(id)
        await model.rotateRight(id)

        await model.undo()

        #expect(model.pages.first?.rotation == .right)
        #expect(model.canUndo)
    }

    @Test("после отката всех правок откатывать снова нечего")
    func afterUndoingEverythingThereIsNothingLeft() async throws {
        let (model, _) = try await makeModel()
        let id = try #require(model.pages.first?.id)
        await model.rotateRight(id)

        await model.undo()

        #expect(model.canUndo == false)
    }

    @Test("откат работает и для вида, и для замазки, а не только для поворота")
    func undoCoversLookAndRedactionToo() async throws {
        let (model, _) = try await makeModel()
        let id = try #require(model.pages.first?.id)

        await model.setLook(.blackAndWhite, for: id)
        await model.addRedaction(
            RedactionArea(rect: NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1)),
            to: id
        )

        await model.undo()
        #expect(model.pages.first?.redactions.isEmpty == true)
        #expect(model.pages.first?.look == .blackAndWhite)

        await model.undo()
        #expect(model.pages.first?.look == .color)
    }
}
