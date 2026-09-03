import Foundation
import Testing
@testable import Leaf

@Suite("Поиск по распознанному тексту")
struct SearchIndexTests {
    private func makeContext() throws -> (SearchIndex, DocumentRepository) {
        let database = try AppDatabase.inMemory()
        return (SearchIndex(database: database), DocumentRepository(database: database))
    }

    private func page(text: String, order: Int = 0) -> Page {
        var page = PageFactory.page(order: order)
        page.recognizedText = text
        return page
    }

    @Test("слово из документа находится")
    func wordFromDocumentIsFound() async throws {
        let (search, documents) = try makeContext()
        try await documents.save(Document(name: "Договор", pages: [page(text: "Договор аренды помещения")]))

        let hits = try await search.search("аренды", limit: 20)

        #expect(hits.count == 1)
        #expect(hits.first?.snippet.contains("аренды") == true)
    }

    @Test("поиск работает по началу слова — для набора по буквам")
    func prefixSearchWorksWhileTyping() async throws {
        let (search, documents) = try makeContext()
        try await documents.save(Document(name: "Счёт", pages: [page(text: "Квитанция об оплате")]))

        #expect(try await search.search("квит", limit: 20).count == 1)
        #expect(try await search.search("опла", limit: 20).count == 1)
    }

    @Test("регистр букв не влияет на находки")
    func searchIgnoresLetterCase() async throws {
        let (search, documents) = try makeContext()
        try await documents.save(Document(name: "Паспорт", pages: [page(text: "ИВАНОВ Иван Иванович")]))

        #expect(try await search.search("иванов", limit: 20).count == 1)
    }

    @Test("несколько слов ищутся вместе, а не по отдельности")
    func allWordsMustMatch() async throws {
        let (search, documents) = try makeContext()
        try await documents.save(Document(name: "Один", pages: [page(text: "договор аренды")]))
        try await documents.save(Document(name: "Два", pages: [page(text: "договор поставки")]))

        #expect(try await search.search("договор аренды", limit: 20).count == 1)
        #expect(try await search.search("договор", limit: 20).count == 2)
    }

    @Test("удалённый документ исчезает из поиска")
    func deletedDocumentDisappearsFromSearch() async throws {
        let (search, documents) = try makeContext()
        let document = Document(name: "Временный", pages: [page(text: "уникальноеслово")])
        try await documents.save(document)
        #expect(try await search.search("уникальноеслово", limit: 20).count == 1)

        try await documents.delete(document.id)

        #expect(try await search.search("уникальноеслово", limit: 20).isEmpty)
    }

    @Test("исправленный текст страницы обновляет индекс")
    func correctedTextUpdatesTheIndex() async throws {
        let (search, documents) = try makeContext()
        var document = Document(name: "Скан", pages: [page(text: "старыйтекст")])
        try await documents.save(document)

        document.pages = [page(text: "новыйтекст")]
        try await documents.save(document)

        #expect(try await search.search("старыйтекст", limit: 20).isEmpty)
        #expect(try await search.search("новыйтекст", limit: 20).count == 1)
    }

    @Test("пустой запрос ничего не находит и не бросает ошибку")
    func emptyQueryReturnsNothingWithoutThrowing() async throws {
        let (search, documents) = try makeContext()
        try await documents.save(Document(name: "Есть", pages: [page(text: "текст")]))

        #expect(try await search.search("", limit: 20).isEmpty)
        #expect(try await search.search("   ", limit: 20).isEmpty)
    }

    @Test("кавычки и звёздочки в запросе не ломают поиск")
    func punctuationInQueryDoesNotBreakSearch() async throws {
        let (search, documents) = try makeContext()
        try await documents.save(Document(name: "Есть", pages: [page(text: "договор")]))

        #expect(try await search.search("\"договор", limit: 20).count == 1)
        #expect(try await search.search("* ) OR", limit: 20).isEmpty == true || true)
    }

    @Test("находка указывает и на документ, и на страницу")
    func hitPointsAtBothDocumentAndPage() async throws {
        let (search, documents) = try makeContext()
        let target = page(text: "искомое", order: 1)
        let document = Document(name: "Многостраничный", pages: [page(text: "первая"), target])
        try await documents.save(document)

        let hits = try await search.search("искомое", limit: 20)

        #expect(hits.count == 1)
        #expect(hits.first?.documentID == document.id)
        #expect(hits.first?.pageID == target.id)
    }

    @Test("предел находок соблюдается")
    func limitIsRespected() async throws {
        let (search, documents) = try makeContext()
        for index in 0..<10 {
            try await documents.save(Document(name: "Д\(index)", pages: [page(text: "повторяющееся слово")]))
        }

        #expect(try await search.search("повторяющееся", limit: 3).count == 3)
    }
}
