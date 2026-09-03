import CoreGraphics
import Testing
@testable import Leaf

@Suite("Распознавание текста")
struct TextRecognizerTests {
    private let recognizer = TextRecognizer()

    @Test("надпись на листе распознаётся")
    func captionOnSheetIsRecognized() async throws {
        let lines = try await recognizer.recognize(ImageFactory.text("ДОГОВОР"))

        #expect(lines.isEmpty == false)
        let joined = lines.map(\.text).joined(separator: " ").uppercased()
        #expect(joined.contains("ДОГОВОР"))
    }

    @Test("латиница распознаётся наравне с кириллицей")
    func latinIsRecognizedAlongsideCyrillic() async throws {
        let lines = try await recognizer.recognize(ImageFactory.text("INVOICE"))

        let joined = lines.map(\.text).joined(separator: " ").uppercased()
        #expect(joined.contains("INVOICE"))
    }

    @Test("рамка строки лежит внутри страницы")
    func lineBoxStaysInsideThePage() async throws {
        let lines = try await recognizer.recognize(ImageFactory.text("ПАСПОРТ"))
        let first = try #require(lines.first)

        #expect(first.box.x >= 0)
        #expect(first.box.y >= 0)
        #expect(first.box.maxX <= 1.001)
        #expect(first.box.maxY <= 1.001)
        #expect(first.box.height > 0)
    }

    @Test("рамка отсчитывается сверху листа, как обрезка и замазка")
    func lineBoxIsMeasuredFromTheTopOfTheSheet() async throws {
        // Иначе замазка накрыла бы зеркальную часть листа: человек закрыл бы
        // номер карты, а закрылась бы подпись.
        let top = try await recognizer.recognize(ImageFactory.text("ВЕРХ", nearTop: true))
        let bottom = try await recognizer.recognize(ImageFactory.text("НИЗ", nearTop: false))

        let topLine = try #require(top.first)
        let bottomLine = try #require(bottom.first)

        #expect(topLine.box.y < 0.4)
        #expect(bottomLine.box.y > 0.5)
    }

    @Test("пустой лист не даёт ни строк, ни ошибки")
    func blankSheetGivesNeitherLinesNorError() async throws {
        let lines = try await recognizer.recognize(ImageFactory.solid(width: 600, height: 400, gray: 1.0))

        #expect(lines.isEmpty)
    }

    @Test("распознанный текст собирается в одну строку для хранения")
    func recognizedTextIsJoinedForStorage() async throws {
        let lines = try await recognizer.recognize(ImageFactory.text("СЧЁТ"))

        #expect(TextRecognizer.plainText(from: lines).isEmpty == false)
        #expect(TextRecognizer.plainText(from: []).isEmpty)
    }
}
