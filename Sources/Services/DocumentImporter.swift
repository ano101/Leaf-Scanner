import CoreGraphics
import Foundation
import ImageIO
import PDFKit

public enum ImportError: Error, Equatable, Sendable {
    case unreadableFile(String)
    case nothingImported
}

/// Ввод готовых файлов: снимки документов, сделанные раньше, и присланные PDF.
///
/// У людей архив бумаг уже лежит в «Фото» и «Файлах». Приложение, которое
/// умеет только снимать заново, заставляет переснимать то, что снято.
public struct DocumentImporter: Sendable {
    private let importer: ScanImporter

    public init(importer: ScanImporter) {
        self.importer = importer
    }

    public func pages(fromImageData data: [Data]) async throws -> [Page] {
        var images: [CGImage] = []

        for item in data {
            guard let source = CGImageSourceCreateWithData(item as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                continue
            }
            images.append(image)
        }

        guard images.isEmpty == false else { throw ImportError.nothingImported }
        return try await importer.makePages(from: images)
    }

    /// Страницы PDF переводятся в изображения: дальше документ живёт по общим
    /// правилам — поворачивается, замазывается, ужимается под нужный вес.
    public func pages(fromPDF url: URL) async throws -> [Page] {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        guard let document = PDFDocument(url: url) else {
            throw ImportError.unreadableFile(url.lastPathComponent)
        }

        var images: [CGImage] = []
        let scale = 2.0

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }

            let bounds = page.bounds(for: .mediaBox)
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            guard size.width >= 1, size.height >= 1 else { continue }

            guard let context = CGContext(
                data: nil,
                width: Int(size.width),
                height: Int(size.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { continue }

            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)

            if let image = context.makeImage() { images.append(image) }
        }

        guard images.isEmpty == false else { throw ImportError.nothingImported }
        return try await importer.makePages(from: images)
    }
}
