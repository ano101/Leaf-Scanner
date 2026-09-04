import Foundation

/// Состояние экрана архива.
///
/// Отказ здесь — тоже состояние с действием, а не надпись. «Не удалось
/// загрузить» без кнопки «повторить» — это тупик, из которого человек выходит
/// только перезапуском приложения.
@MainActor
@Observable
public final class ArchiveModel {
    public enum State: Equatable, Sendable {
        case loading
        case ready
        case failed(messageKey: String)
    }

    public private(set) var groups: [DocumentGroup] = []
    public private(set) var folders: [Folder] = []
    public private(set) var hits: [SearchHit] = []
    public private(set) var state: State = .loading

    public var query: String = ""
    public var folderID: FolderID?
    /// Выделенные документы. Отдельно от списка, потому что список
    /// перечитывается, а выбор человека переживать это обязан.
    public var selection: Set<DocumentID> = []

    private let documents: any DocumentRepositoryProtocol
    private let folderStore: any FolderRepositoryProtocol
    private let search: any SearchIndexProtocol
    private let now: @Sendable () -> Date

    public init(
        documents: any DocumentRepositoryProtocol,
        folders: any FolderRepositoryProtocol,
        search: any SearchIndexProtocol,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.documents = documents
        self.folderStore = folders
        self.search = search
        self.now = now
    }

    public var isSearching: Bool {
        query.trimmingCharacters(in: .whitespaces).isEmpty == false
    }

    public var isEmpty: Bool {
        groups.isEmpty && folders.isEmpty
    }

    public func load() async {
        state = .loading
        do {
            let stored = try await documents.all(inFolder: folderID)
            folders = try await folderStore.all(inParent: folderID)
            groups = DocumentGrouping.group(stored, now: now())
            state = .ready
        } catch {
            groups = []
            folders = []
            state = .failed(messageKey: "archive.error.load")
        }
    }

    public func runSearch() async {
        guard isSearching else {
            hits = []
            return
        }

        do {
            hits = try await search.search(query, limit: 100)
        } catch {
            hits = []
            state = .failed(messageKey: "archive.error.search")
        }
    }

    public func toggleSelection(_ id: DocumentID) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    /// Объединение в порядке, в котором документы лежат на экране, а не
    /// в порядке нажатий: человек видит список сверху вниз и ждёт того же
    /// порядка страниц.
    public func mergeSelection(into name: String) async {
        let chosen = orderedSelection()
        guard chosen.count > 1 else {
            state = .failed(messageKey: "archive.error.mergeOne")
            return
        }

        let trimmed = name.trimmingCharacters(in: .whitespaces)
        do {
            _ = try await documents.merge(chosen, into: trimmed.isEmpty ? defaultMergeName() : trimmed)
            selection = []
            await load()
        } catch {
            state = .failed(messageKey: "archive.error.merge")
        }
    }

    public func deleteSelection() async {
        let chosen = selection
        guard chosen.isEmpty == false else { return }

        do {
            for id in chosen {
                try await documents.delete(id)
            }
            selection = []
            await load()
        } catch {
            state = .failed(messageKey: "archive.error.delete")
        }
    }

    /// Имя по умолчанию берётся у первого документа: «Объединённый» ничего
    /// не говорит человеку, который через месяц ищет этот документ глазами.
    public func defaultMergeName() -> String {
        orderedDocuments().first { selection.contains($0.id) }?.name
            ?? ScanImporter.suggestedName(from: nil, date: now())
    }

    private func orderedSelection() -> [DocumentID] {
        orderedDocuments().map(\.id).filter { selection.contains($0) }
    }

    private func orderedDocuments() -> [Document] {
        groups.flatMap(\.documents)
    }

    public func delete(_ id: DocumentID) async {
        do {
            try await documents.delete(id)
            await load()
        } catch {
            state = .failed(messageKey: "archive.error.delete")
        }
    }

    public func createFolder(named name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard trimmed.isEmpty == false else { return }

        do {
            try await folderStore.save(Folder(name: trimmed, parentID: folderID))
            await load()
        } catch {
            state = .failed(messageKey: "archive.error.folder")
        }
    }
}
