import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import Leaf

@Suite("Безвозвратная замазка")
struct RedactionTests {
    private let renderer = PageRenderer()
    private let builder = PDFBuilder()

    private let secret = NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.1)
    private let safe = NormalizedRect(x: 0.1, y: 0.6, width: 0.5, height: 0.1)

    @Test("замазанный текст не попадает в текстовый слой готового файла")
    func redactedTextNeverReachesTheTextLayer() throws {
        let page = RenderedPage(
            image: ImageFactory.solid(width: 600, height: 800),
            text: [
                RecognizedLine(text: "4276130000001111", box: secret),
                RecognizedLine(text: "ДоговорАренды", box: safe),
            ],
            redactions: [RedactionArea(rect: secret)]
        )

        let data = try builder.build(pages: [page], password: nil)
        let extracted = try #require(PDFDocument(data: data)).string ?? ""

        #expect(extracted.contains("4276") == false)
        #expect(extracted.contains("ДоговорАренды"))
    }

    @Test("строка, задетая замазкой лишь частично, исключается целиком")
    func partiallyCoveredLineIsRemovedEntirely() throws {
        let overlapping = NormalizedRect(x: 0.0, y: 0.12, width: 0.2, height: 0.02)
        let page = RenderedPage(
            image: ImageFactory.solid(width: 400, height: 400),
            text: [RecognizedLine(text: "СерияИНомер", box: secret)],
            redactions: [RedactionArea(rect: overlapping)]
        )

        let data = try builder.build(pages: [page], password: nil)
        let extracted = try #require(PDFDocument(data: data)).string ?? ""

        #expect(extracted.contains("Серия") == false)
    }

    @Test("замазанная область изображения одноцветна — пикселей под ней нет")
    func redactedPixelsAreDestroyedNotCovered() throws {
        // Область нарочно пересекает границу чёрной и белой половин.
        // Без уничтожения пикселей внутри неё осталось бы два уровня яркости,
        // и проверка отличает настоящую замазку от совпадения.
        let crossingHalves = NormalizedRect(x: 0, y: 0.25, width: 1, height: 0.5)
        var page = Page(id: PageID(), order: 0, look: .asShot)
        page.redactions = [RedactionArea(rect: crossingHalves)]

        let source = ImageFactory.halves(width: 200, height: 200)
        let sampled = CGRect(x: 10, y: 60, width: 180, height: 80)

        let untouched = try renderer.render(source, page: {
            var plain = page
            plain.redactions = []
            return plain
        }(), look: .color, scale: 1.0)
        let before = try #require(untouched.cropping(to: sampled))
        #expect(PixelSampler.luminanceLevels(of: before).count == 2, "фикстура обязана содержать два тона")

        let result = try renderer.render(source, page: page, look: .color, scale: 1.0)
        let after = try #require(result.cropping(to: sampled))
        #expect(PixelSampler.luminanceLevels(of: after).count == 1)
    }

    @Test("без замазки текст остаётся на месте")
    func withoutRedactionTextStays() throws {
        let page = RenderedPage(
            image: ImageFactory.solid(width: 400, height: 400),
            text: [RecognizedLine(text: "ВидимыйТекст", box: secret)],
            redactions: []
        )

        let data = try builder.build(pages: [page], password: nil)
        let extracted = try #require(PDFDocument(data: data)).string ?? ""

        #expect(extracted.contains("ВидимыйТекст"))
    }
}
