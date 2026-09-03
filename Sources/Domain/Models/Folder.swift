import Foundation

public typealias FolderID = Identifier<Folder>

public struct Folder: Identifiable, Hashable, Sendable {
    public let id: FolderID
    public var name: String
    public var parentID: FolderID?
    public var createdAt: Date

    public init(
        id: FolderID = .init(),
        name: String,
        parentID: FolderID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.createdAt = createdAt
    }
}
