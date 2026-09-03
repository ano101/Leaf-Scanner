import Foundation
import GRDB

public protocol FolderRepositoryProtocol: Sendable {
    func save(_ folder: Folder) async throws
    func all(inParent parentID: FolderID?) async throws -> [Folder]
    func delete(_ id: FolderID) async throws
}

public struct FolderRepository: FolderRepositoryProtocol {
    let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func save(_ folder: Folder) async throws {
        let record = FolderRecord(folder: folder)
        try await database.writer.write { db in
            try record.save(db)
        }
    }

    public func all(inParent parentID: FolderID?) async throws -> [Folder] {
        try await database.writer.read { db in
            try FolderRecord
                .filter(Column("parentId") == parentID?.raw.uuidString)
                .order(Column("name"))
                .fetchAll(db)
                .map { try $0.toFolder() }
        }
    }

    public func delete(_ id: FolderID) async throws {
        try await database.writer.write { db in
            _ = try FolderRecord.deleteOne(db, key: id.raw.uuidString)
        }
    }
}
