import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import Leaf

/// Что именно уходит получателю.
///
/// Снимок с телефона несёт в себе место съёмки, модель устройства и точное
/// время. Приложение, которое просто перекладывает такой снимок в файл,
/// отправляет вместе с договором координаты квартиры — молча.
@Suite("Метаданные исходящих файлов")
struct MetadataTests {
    private func pages(_ count: Int) -> [Page] {
        (0..<count).map { Page(order: $0, look: .asShot) }
    }

    private func properties(of data: Data) -> [String: Any] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { return [:] }
        return properties
    }

    @Test("в изображении, снятом с геометкой, метки не остаётся")
    func geotaggedPhotoLosesItsLocation() async throws {
        let tagged = try photoWithLocation()
        // Проверка самой фикстуры: без неё тест доказывал бы пустоту.
        #expect(properties(of: tagged)[kCGImagePropertyGPSDictionary as String] != nil)

        let source = try CGImageSourceCreateWithData(tagged as CFData, nil) ?? { throw Failure() }()
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let page = Page(order: 0, look: .asShot)

        let fitter = SizeFitter(source: SingleImageSource(id: page.id, image: image))
        let outcome = try await fitter.fit(
            pages: [page], text: [:], limitBytes: 20_000_000,
            look: .asShot, format: .jpeg, baseName: "Скан"
        )

        guard case let .fitted(result) = outcome, let file = result.files.first else {
            Issue.record("ожидался готовый файл, пришло \(outcome)")
            return
        }

        let outgoing = properties(of: file.data)

        // Место съёмки не должно уйти ни в каком виде.
        #expect(outgoing[kCGImagePropertyGPSDictionary as String] == nil)

        // ImageIO дописывает в JPEG собственный EXIF: цветовое
        // пространство и размеры кадра. Это техническое описание файла,
        // а не след человека, и требовать его отсутствия было бы
        // требованием к системе, а не к приложению. Проверяются именно
        // личные поля.
        let exif = outgoing[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        #expect(exif[kCGImagePropertyExifDateTimeOriginal as String] == nil)
        #expect(exif[kCGImagePropertyExifLensModel as String] == nil)

        let tiff = outgoing[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        #expect(tiff[kCGImagePropertyTIFFModel as String] == nil)
        #expect(tiff[kCGImagePropertyTIFFMake as String] == nil)
    }

    @Test("в PDF указано приложение и не указан автор")
    func pdfNamesTheAppAndNoAuthor() throws {
        let data = try PDFBuilder().build(
            pages: [RenderedPage(image: ImageFactory.halves(width: 300, height: 400), text: [])],
            password: nil
        )
        let document = try #require(PDFDocument(data: data))
        let attributes = document.documentAttributes ?? [:]

        #expect(attributes[PDFDocumentAttribute.authorAttribute] == nil)
        let creator = attributes[PDFDocumentAttribute.creatorAttribute] as? String
        #expect(creator == AppInfo.name)
    }

    private struct Failure: Error {}

    /// Снимок с координатами и моделью устройства — то, что лежит
    /// в медиатеке у любого человека.
    private func photoWithLocation() throws -> Data {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ))

        let metadata: [String: Any] = [
            kCGImagePropertyGPSDictionary as String: [
                kCGImagePropertyGPSLatitude as String: 55.751244,
                kCGImagePropertyGPSLatitudeRef as String: "N",
                kCGImagePropertyGPSLongitude as String: 37.618423,
                kCGImagePropertyGPSLongitudeRef as String: "E",
            ],
            kCGImagePropertyExifDictionary as String: [
                kCGImagePropertyExifDateTimeOriginal as String: "2026:09:04 10:20:00",
            ],
            kCGImagePropertyTIFFDictionary as String: [
                kCGImagePropertyTIFFModel as String: "iPhone 17 Pro",
            ],
        ]

        CGImageDestinationAddImage(
            destination,
            ImageFactory.halves(width: 400, height: 500),
            metadata as CFDictionary
        )
        #expect(CGImageDestinationFinalize(destination))

        return data as Data
    }
}

private struct SingleImageSource: PageImageSource {
    let id: PageID
    let image: CGImage

    func image(for requested: PageID) async throws -> CGImage {
        guard requested == id else { throw PageStoreError.pageNotFound(requested) }
        return image
    }
}
