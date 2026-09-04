import Foundation
import GRDB

struct PageRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "page"

    var id: String
    var documentId: String
    var ordinal: Int
    var rotation: Int
    var look: String
    var cropJson: String?
    var redactionsJson: String?
    /// SQLite хранит целые со знаком, поэтому хеш кладётся побитово
    /// и восстанавливается тем же способом — без потери значений.
    var perceptualHash: Int64?
    var recognizedText: String?

    init(page: Page, documentId: DocumentID) throws {
        self.id = page.id.raw.uuidString
        self.documentId = documentId.raw.uuidString
        self.ordinal = page.order
        self.rotation = page.rotation.rawValue
        self.look = page.look.rawValue
        self.cropJson = try RecordCoding.encode(page.crop)
        self.redactionsJson = try RecordCoding.encode(page.redactions)
        self.perceptualHash = page.perceptualHash.map { Int64(bitPattern: $0) }
        self.recognizedText = page.recognizedText
    }

    func toPage() throws -> Page {
        guard let uuid = UUID(uuidString: id) else {
            throw RepositoryError.corruptedRecord(table: Self.databaseTableName, id: id)
        }

        return Page(
            id: PageID(uuid),
            order: ordinal,
            rotation: Rotation(rawValue: rotation) ?? .none,
            look: PageLook(rawValue: look) ?? .color,
            crop: try RecordCoding.decode(NormalizedQuad.self, from: cropJson),
            redactions: try RecordCoding.decode([RedactionArea].self, from: redactionsJson) ?? [],
            perceptualHash: perceptualHash.map { UInt64(bitPattern: $0) },
            recognizedText: recognizedText
        )
    }
}
