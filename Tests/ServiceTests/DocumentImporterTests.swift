import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Leaf

@Suite("Импорт готовых файлов")
struct DocumentImporterTests {
    private func makeImporter() throws -> (DocumentImporter, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("leaf-import-\(UUID().uuidString)")
        let store = try PageStore(root: root)
        return (DocumentImporter(importer: ScanImporter(store: store)), root)
    }

    private func jpegData(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test("снимки из фотографий становятся страницами по порядку")
    func photosBecomePagesInOrder() async throws {
        let (importer, root) = try makeImporter()
        defer { try? FileManager.default.removeItem(at: root) }

        let pages = try await importer.pages(fromImageData: [
            try jpegData(ImageFactory.halves(width: 400, height: 500)),
            try jpegData(ImageFactory.gradient(width: 400, height: 500)),
        ])

        #expect(pages.count == 2)
        #expect(pages.map(\.order) == [0, 1])
    }

    @Test("испорченный файл не создаёт пустой документ, а объясняет отказ")
    func brokenFileExplainsItselfInsteadOfCreatingEmptyDocument() async throws {
        let (importer, root) = try makeImporter()
        defer { try? FileManager.default.removeItem(at: root) }

        await #expect(throws: ImportError.nothingImported) {
            _ = try await importer.pages(fromImageData: [Data([0x00, 0x01, 0x02])])
        }
    }

    @Test("страницы PDF переводятся в изображения и живут по общим правилам")
    func pdfPagesBecomeRegularPages() async throws {
        let (importer, root) = try makeImporter()
        defer { try? FileManager.default.removeItem(at: root) }

        let pdf = try PDFBuilder().build(
            pages: [
                RenderedPage(image: ImageFactory.halves(width: 300, height: 400), text: []),
                RenderedPage(image: ImageFactory.gradient(width: 300, height: 400), text: []),
            ],
            password: nil
        )
        let url = root.appendingPathComponent("sample.pdf")
        try pdf.write(to: url)

        let pages = try await importer.pages(fromPDF: url)

        #expect(pages.count == 2)
        #expect(pages.allSatisfy { $0.perceptualHash != nil })
    }

    @Test("файл, который не является PDF, отклоняется с именем файла")
    func nonPdfFileIsRejectedWithItsName() async throws {
        let (importer, root) = try makeImporter()
        defer { try? FileManager.default.removeItem(at: root) }

        let url = root.appendingPathComponent("notes.pdf")
        try Data("это не pdf".utf8).write(to: url)

        await #expect(throws: ImportError.unreadableFile("notes.pdf")) {
            _ = try await importer.pages(fromPDF: url)
        }
    }
}
