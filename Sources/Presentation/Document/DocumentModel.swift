import Foundation

/// Состояние экрана документа. Все правки идут через модель и сразу
/// сохраняются: «не сохранил и потерял» для архива документов недопустимо.
@MainActor
@Observable
public final class DocumentModel {
    public enum State: Equatable, Sendable {
        case ready
        case failed(messageKey: String)
    }

    public private(set) var document: Document
    public private(set) var state: State = .ready
    public var selection: Set<PageID> = []

    private let documents: any DocumentRepositoryProtocol

    public init(document: Document, documents: any DocumentRepositoryProtocol) {
        self.document = document
        self.documents = documents
    }

    public var pages: [Page] {
        PageOrdering.sorted(document.pages)
    }

    public func rotateRight(_ pageID: PageID) async {
        await update { document in
            guard let index = document.pages.firstIndex(where: { $0.id == pageID }) else { return }
            document.pages[index].rotation = document.pages[index].rotation.turnedRight()
        }
    }

    public func rotateLeft(_ pageID: PageID) async {
        await update { document in
            guard let index = document.pages.firstIndex(where: { $0.id == pageID }) else { return }
            document.pages[index].rotation = document.pages[index].rotation.turnedLeft()
        }
    }

    public func toggleSelection(_ pageID: PageID) {
        if selection.contains(pageID) {
            selection.remove(pageID)
        } else {
            selection.insert(pageID)
        }
    }

    public func rotateSelectionRight() async {
        let chosen = selection
        guard chosen.isEmpty == false else { return }

        await update { document in
            for index in document.pages.indices where chosen.contains(document.pages[index].id) {
                document.pages[index].rotation = document.pages[index].rotation.turnedRight()
            }
        }
    }

    /// Удалить все страницы разом нельзя: документ без страниц — это строка
    /// в архиве, которую человек откроет и не поймёт, зачем она осталась.
    public func deleteSelection() async {
        let chosen = selection
        guard chosen.isEmpty == false else { return }
        guard chosen.count < document.pages.count else {
            state = .failed(messageKey: "document.error.lastPage")
            return
        }

        await update { document in
            document.pages.removeAll { chosen.contains($0.id) }
            document.pages = PageOrdering.renumbered(PageOrdering.sorted(document.pages))
        }
        selection = []
    }

    public func rotateAllRight() async {
        await update { document in
            for index in document.pages.indices {
                document.pages[index].rotation = document.pages[index].rotation.turnedRight()
            }
        }
    }

    public func setLook(_ look: PageLook, for pageID: PageID) async {
        await update { document in
            guard let index = document.pages.firstIndex(where: { $0.id == pageID }) else { return }
            document.pages[index].look = look
        }
    }

    /// Вид относится ко всему документу, как у настоящего сканера: человек
    /// выбирает его один раз на пачку, а не заново на каждый лист.
    public func setLookForAllPages(_ look: PageLook) async {
        await update { document in
            for index in document.pages.indices {
                document.pages[index].look = look
            }
        }
    }

    public func addRedaction(_ area: RedactionArea, to pageID: PageID) async {
        await update { document in
            guard let index = document.pages.firstIndex(where: { $0.id == pageID }) else { return }
            document.pages[index].redactions.append(area)
        }
    }

    public func removeRedactions(from pageID: PageID) async {
        await update { document in
            guard let index = document.pages.firstIndex(where: { $0.id == pageID }) else { return }
            document.pages[index].redactions = []
        }
    }

    public func move(from source: Int, to destination: Int) async {
        await update { document in
            document.pages = PageOrdering.move(PageOrdering.sorted(document.pages), from: source, to: destination)
        }
    }

    /// Последняя страница не удаляется: документ без страниц — это строка
    /// в архиве, которую человек откроет и не поймёт, зачем она осталась.
    /// Удалять его целиком нужно из архива, осознанно.
    public func deletePage(_ pageID: PageID) async {
        guard document.pages.count > 1 else {
            state = .failed(messageKey: "document.error.lastPage")
            return
        }

        await update { document in
            document.pages.removeAll { $0.id == pageID }
            document.pages = PageOrdering.renumbered(PageOrdering.sorted(document.pages))
        }
    }

    public func rename(to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard trimmed.isEmpty == false else { return }

        await update { document in
            document.name = trimmed
            document.isNameAutomatic = false
        }
    }

    public func split(after index: Int, tailName: String) async -> Document? {
        do {
            let result = try await documents.split(document.id, after: index, tailName: tailName)
            document = result.head
            state = .ready
            return result.tail
        } catch RepositoryError.splitWouldLeaveEmptyDocument {
            state = .failed(messageKey: "document.error.splitEdge")
            return nil
        } catch {
            state = .failed(messageKey: "document.error.save")
            return nil
        }
    }

    private func update(_ change: (inout Document) -> Void) async {
        var edited = document
        change(&edited)
        edited.updatedAt = Date()

        do {
            try await documents.save(edited)
            document = edited
            state = .ready
        } catch {
            // Правка не применяется к состоянию экрана, если её не удалось
            // сохранить: показанное обязано совпадать с записанным.
            state = .failed(messageKey: "document.error.save")
        }
    }
}
