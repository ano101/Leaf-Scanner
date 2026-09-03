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
