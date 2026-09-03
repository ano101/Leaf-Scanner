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

    public init(
        id: DocumentID = .init(),
        name: String,
        folderID: FolderID? = nil,
        tagIDs: [TagID] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        pages: [Page] = []
    ) {
        self.id = id
        self.name = name
        self.folderID = folderID
        self.tagIDs = tagIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.pages = pages
    }

    public var pageCount: Int { pages.count }
}
