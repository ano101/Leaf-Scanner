import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import Leaf

@Suite("Сборка PDF")
struct PDFBuilderTests {
    private let builder = PDFBuilder()

    private func line(_ text: String, at rect: NormalizedRect) -> RecognizedLine {
        RecognizedLine(text: text, box: rect)
    }

    private func page(text: [RecognizedLine] = []) -> RenderedPage {
        RenderedPage(image: ImageFactory.halves(width: 600, height: 800), text: text)
    }

    @Test("в собранном PDF столько страниц, сколько передано")
    func pageCountMatchesInput() throws {
        let data = try builder.build(pages: [page(), page(), page()], password: nil)
        let document = try #require(PDFDocument(data: data))

        #expect(document.pageCount == 3)
    }

    @Test("распознанный текст извлекается из готового файла")
    func recognizedTextIsExtractableFromResult() throws {
        let pages = [page(text: [line("Договор аренды", at: NormalizedRect(x: 0.1, y: 0.1, width: 0.6, height: 0.05))])]
        let data = try builder.build(pages: pages, password: nil)
        let document = try #require(PDFDocument(data: data))

        let extracted = document.string ?? ""
        #expect(extracted.contains("Договор"))
    }

    @Test("пропорции страницы повторяют пропорции изображения")
    func pageProportionsFollowTheImage() throws {
        let data = try builder.build(pages: [page()], password: nil)
        let document = try #require(PDFDocument(data: data))
        let bounds = try #require(document.page(at: 0)?.bounds(for: .mediaBox))

        let expected = 800.0 / 600.0
        let actual = bounds.height / bounds.width
        #expect(abs(actual - expected) < 0.02)
    }

    @Test("файл с паролем заперт без пароля и открывается с ним")
    func passwordProtectedFileIsLockedWithoutPassword() throws {
        let data = try builder.build(pages: [page()], password: "secret1")
        let document = try #require(PDFDocument(data: data))

        #expect(document.isLocked)
        #expect(document.unlock(withPassword: "secret1"))
    }

    @Test("файл без пароля открывается сразу")
    func fileWithoutPasswordOpensImmediately() throws {
        let data = try builder.build(pages: [page()], password: nil)
        let document = try #require(PDFDocument(data: data))

        #expect(document.isLocked == false)
    }

    @Test("пароль с кириллицей отклоняется явно, а не роняет сборку")
    func cyrillicPasswordIsRejectedExplicitly() throws {
        // Ограничение стандартного механизма защиты PDF: пароль кодируется
        // однобайтово. Молчаливая порча пароля хуже честного отказа —
        // человек узнал бы о ней, только не сумев открыть свой файл.
        #expect(throws: PDFBuildError.passwordNotRepresentable) {
            _ = try builder.build(pages: [page()], password: "тайна")
        }
        #expect(PDFBuilder.isRepresentable("тайна") == false)
        #expect(PDFBuilder.isRepresentable("secret1"))
    }

    @Test("пустой список страниц не даёт пустого файла, а даёт ошибку")
    func emptyPageListGivesErrorNotEmptyFile() throws {
        #expect(throws: PDFBuildError.self) {
            _ = try builder.build(pages: [], password: nil)
        }
    }
}
