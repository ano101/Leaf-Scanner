import Foundation

public typealias DocumentID = Identifier<Document>

public struct Document: Identifiable, Hashable, Sendable {
    public let id: DocumentID
    public var name: String
    public var folderID: FolderID?
    public var tagIDs: [TagID]
    public var createdAt: Date
    public var updatedAt: Date
    public var pages: [Page]
    /// Имя, предложенное приложением, а не заданное человеком. Такое имя
    /// можно уточнить, когда распознавание найдёт заголовок; имя, введённое
    /// человеком, трогать нельзя никогда.
    public var isNameAutomatic: Bool
    /// Дата окончания действия, найденная в тексте. Хранится у документа,
    /// а не у страницы: истекает документ, а не лист бумаги.
    public var expiresAt: Date?

    public init(
        id: DocumentID = .init(),
        name: String,
        folderID: FolderID? = nil,
        tagIDs: [TagID] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        pages: [Page] = [],
        isNameAutomatic: Bool = true,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.folderID = folderID
        self.tagIDs = tagIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.pages = pages
        self.isNameAutomatic = isNameAutomatic
        self.expiresAt = expiresAt
    }

    public var pageCount: Int { pages.count }
}
