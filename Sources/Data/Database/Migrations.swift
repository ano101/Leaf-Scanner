import GRDB

extension AppDatabase {
    /// Миграции только дописываются. Уже выпущенную миграцию не правят —
    /// у людей на устройствах она выполнена, и правка их базу не догонит.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_documents") { db in
            try db.create(table: "folder") { table in
                table.primaryKey("id", .text)
                table.column("name", .text).notNull()
                table.column("parentId", .text).references("folder", onDelete: .cascade)
                table.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "document") { table in
                table.primaryKey("id", .text)
                table.column("name", .text).notNull()
                table.column("folderId", .text).references("folder", onDelete: .setNull)
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "document_folderId", on: "document", columns: ["folderId"])

            try db.create(table: "page") { table in
                table.primaryKey("id", .text)
                table.column("documentId", .text)
                    .notNull()
                    .references("document", onDelete: .cascade)
                table.column("ordinal", .integer).notNull()
                table.column("rotation", .integer).notNull()
                table.column("filter", .text).notNull()
                table.column("cropJson", .text)
                table.column("redactionsJson", .text)
                table.column("perceptualHash", .integer)
                table.column("recognizedText", .text)
            }
            try db.create(index: "page_documentId_ordinal", on: "page", columns: ["documentId", "ordinal"])

            try db.create(table: "tag") { table in
                table.primaryKey("id", .text)
                table.column("name", .text).notNull()
                table.column("colorKey", .text).notNull()
            }

            try db.create(table: "documentTag") { table in
                table.column("documentId", .text)
                    .notNull()
                    .references("document", onDelete: .cascade)
                table.column("tagId", .text)
                    .notNull()
                    .references("tag", onDelete: .cascade)
                table.primaryKey(["documentId", "tagId"])
            }
        }

        return migrator
    }
}
