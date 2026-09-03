import CoreGraphics
import Foundation
import Testing
@testable import Leaf

@Suite("Приём снятых страниц")
struct ScanImporterTests {
    private func makeImporter() throws -> (ScanImporter, PageStore, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("leaf-import-\(UUID().uuidString)")
        let store = try PageStore(root: root)
        return (ScanImporter(store: store), store, root)
    }

    @Test("снятые кадры становятся страницами по порядку")
    func capturedFramesBecomePagesInOrder() async throws {
        let (importer, _, root) = try makeImporter()
        defer { try? FileManager.default.removeItem(at: root) }

        let pages = try await importer.makePages(from: [
            ImageFactory.halves(width: 300, height: 400),
            ImageFactory.gradient(width: 300, height: 400),
        ])

        #expect(pages.count == 2)
        #expect(pages.map(\.order) == [0, 1])
    }

    @Test("оригиналы кадров сохраняются на диск")
    func originalFramesAreStoredOnDisk() async throws {
        let (importer, store, root) = try makeImporter()
        defer { try? FileManager.default.removeItem(at: root) }

        let pages = try await importer.makePages(from: [ImageFactory.halves(width: 200, height: 200)])
        let first = try #require(pages.first)

        #expect(FileManager.default.fileExists(atPath: store.originalURL(for: first.id).path))
    }

    @Test("отпечаток считается сразу — повтор виден до сохранения документа")
    func fingerprintIsComputedImmediately() async throws {
        let (importer, _, root) = try makeImporter()
        defer { try? FileManager.default.removeItem(at: root) }

        let pages = try await importer.makePages(from: [ImageFactory.gradient(width: 300, height: 300)])

        #expect(pages.first?.perceptualHash != nil)
    }

    @Test("распознавание не задерживает съёмку — текста ещё нет")
    func recognitionDoesNotHoldUpCapture() async throws {
        let (importer, _, root) = try makeImporter()
        defer { try? FileManager.default.removeItem(at: root) }

        let pages = try await importer.makePages(from: [ImageFactory.text("ДОГОВОР")])

        #expect(pages.first?.recognizedText == nil)
    }

    @Test("две пачки собираются в двусторонний документ")
    func twoStacksBecomeDoubleSidedDocument() async throws {
        let (importer, _, root) = try makeImporter()
        defer { try? FileManager.default.removeItem(at: root) }

        let fronts = try await importer.makePages(from: [
            ImageFactory.halves(width: 200, height: 200),
            ImageFactory.gradient(width: 200, height: 200),
        ])
        let backs = try await importer.makePages(from: [
            ImageFactory.solid(width: 200, height: 200, gray: 0.2),
            ImageFactory.solid(width: 200, height: 200, gray: 0.8),
        ])

        let combined = DuplexInterleaver.interleave(fronts: fronts, backs: backs)

        #expect(combined.count == 4)
        #expect(combined.map(\.id) == [fronts[0].id, backs[1].id, fronts[1].id, backs[0].id])
    }

    @Test("пустая съёмка не создаёт ни одной страницы")
    func emptyCaptureCreatesNoPages() async throws {
        let (importer, _, root) = try makeImporter()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(try await importer.makePages(from: []).isEmpty)
    }

    @Test("название документа берётся из даты, когда текста ещё нет")
    func documentNameFallsBackToDate() {
        let name = ScanImporter.suggestedName(from: nil, date: Date(timeIntervalSince1970: 0))

        #expect(name.isEmpty == false)
        #expect(name.contains("1970"))
    }

    @Test("название берётся из первой содержательной строки распознанного текста")
    func documentNameComesFromFirstMeaningfulLine() {
        let name = ScanImporter.suggestedName(
            from: "  \n\nДоговор аренды помещения\nот 12.03.2026",
            date: Date()
        )

        #expect(name == "Договор аренды помещения")
    }

    @Test("слишком длинная первая строка обрезается, а не растягивает список")
    func overlyLongFirstLineIsTrimmed() {
        let long = String(repeating: "Очень длинное название ", count: 20)
        let name = ScanImporter.suggestedName(from: long, date: Date())

        #expect(name.count <= ScanImporter.maxNameLength)
    }
}
