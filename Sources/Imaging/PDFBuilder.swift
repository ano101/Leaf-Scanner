import CoreGraphics
import CoreText
import Foundation

/// Строка распознанного текста и её место на странице в долях от размера.
public struct RecognizedLine: Equatable, Sendable, Codable {
    public let text: String
    public let box: NormalizedRect

    public init(text: String, box: NormalizedRect) {
        self.text = text
        self.box = box
    }
}

/// Страница, готовая к записи в файл: пиксели уже обработаны рендерером.
public struct RenderedPage: Sendable {
    public let image: CGImage
    public let text: [RecognizedLine]

    public init(image: CGImage, text: [RecognizedLine]) {
        self.image = image
        self.text = text
    }
}

public enum PDFBuildError: Error, Equatable, Sendable {
    case noPages
    case contextCreationFailed
    /// Стандартный механизм защиты PDF кодирует пароль однобайтово.
    /// Кириллица в него не помещается: файл либо не соберётся, либо
    /// откроется не тем паролем, который человек ввёл.
    case passwordNotRepresentable
}

/// Единственное место, где собирается файл, уходящий наружу.
///
/// Текст пишется невидимым слоем поверх изображения: файл выглядит как скан,
/// но ищется и копируется как текст — в любом просмотрщике, а не только
/// в этом приложении.
public struct PDFBuilder: Sendable {
    public init() {}

    /// Пароль проверяется до сборки, чтобы отказ был внятным.
    /// Ограничение принадлежит формату PDF, а не приложению.
    public static func isRepresentable(_ password: String) -> Bool {
        password.allSatisfy { $0.isASCII } && password.isEmpty == false
    }

    public func build(pages: [RenderedPage], password: String?) throws -> Data {
        guard pages.isEmpty == false else { throw PDFBuildError.noPages }

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else {
            throw PDFBuildError.contextCreationFailed
        }

        var documentInfo: [String: Any] = [:]
        if let password, password.isEmpty == false {
            guard Self.isRepresentable(password) else {
                throw PDFBuildError.passwordNotRepresentable
            }
            // Оба пароля задаются одинаковыми: без пароля владельца
            // просмотрщики считают документ незащищённым.
            documentInfo[kCGPDFContextUserPassword as String] = password
            documentInfo[kCGPDFContextOwnerPassword as String] = password
        }

        var firstBox = box(for: pages[0].image)
        guard let context = CGContext(
            consumer: consumer,
            mediaBox: &firstBox,
            documentInfo as CFDictionary
        ) else {
            throw PDFBuildError.contextCreationFailed
        }

        for page in pages {
            var mediaBox = box(for: page.image)
            context.beginPage(mediaBox: &mediaBox)
            context.draw(page.image, in: mediaBox)
            draw(page.text, in: mediaBox, context: context)
            context.endPage()
        }

        context.closePDF()
        return data as Data
    }

    /// Размер страницы задаётся в точках из расчёта 200 точек на дюйм:
    /// при печати лист получается ожидаемого формата, а не размером
    /// в пиксель за точку.
    private func box(for image: CGImage) -> CGRect {
        let pointsPerInch = 72.0
        let scanResolution = 200.0
        let factor = pointsPerInch / scanResolution

        return CGRect(
            x: 0,
            y: 0,
            width: (Double(image.width) * factor).rounded(),
            height: (Double(image.height) * factor).rounded()
        )
    }

    private func draw(_ lines: [RecognizedLine], in box: CGRect, context: CGContext) {
        guard lines.isEmpty == false else { return }

        context.saveGState()
        // Режим невидимого текста: слой существует для поиска и копирования,
        // но не портит вид скана.
        context.setTextDrawingMode(.invisible)

        for line in lines where line.text.isEmpty == false {
            let height = max(line.box.height * box.height, 1)
            let font = CTFontCreateWithName("Helvetica" as CFString, height, nil)
            let attributed = NSAttributedString(
                string: line.text,
                attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
            )
            let typeset = CTLineCreateWithAttributedString(attributed)

            context.textPosition = CGPoint(
                x: line.box.x * box.width,
                // Доли считаются сверху, начало координат страницы внизу.
                y: (1 - line.box.maxY) * box.height
            )
            CTLineDraw(typeset, context)
        }

        context.restoreGState()
    }
}
