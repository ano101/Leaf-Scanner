import CoreGraphics
import CoreText
import Foundation

/// Синтетические изображения для тестов: настоящая съёмка недоступна,
/// а проверять нужно размеры и содержимое, а не качество кадра.
enum ImageFactory {
    static func solid(width: Int, height: Int, gray: Double = 0.5) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
        guard let context else {
            preconditionFailure("не удалось создать контекст рисования для теста")
        }

        context.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let image = context.makeImage() else {
            preconditionFailure("не удалось получить изображение из контекста")
        }
        return image
    }

    /// Верхняя половина чёрная, нижняя белая — по ним видно повороты и обрезку.
    ///
    /// Начало координат контекста рисования внизу слева, поэтому «верх»
    /// изображения — это большие значения y, а не нулевые.
    static func halves(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
        guard let context else {
            preconditionFailure("не удалось создать контекст рисования для теста")
        }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: height / 2, width: width, height: height / 2))

        guard let image = context.makeImage() else {
            preconditionFailure("не удалось получить изображение из контекста")
        }
        return image
    }

    /// Мелкая рябь: такое изображение сжимается заметно хуже однотонного,
    /// поэтому по нему проверяется поиск самой тяжёлой страницы.
    static func noisy(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
        guard let context else {
            preconditionFailure("не удалось создать контекст рисования для теста")
        }

        var generator = SystemRandomNumberGenerator()
        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) {
                let value = Double.random(in: 0...1, using: &generator)
                context.setFillColor(CGColor(red: value, green: value, blue: value, alpha: 1))
                context.fill(CGRect(x: x, y: y, width: 2, height: 2))
            }
        }

        guard let image = context.makeImage() else {
            preconditionFailure("не удалось получить изображение из контекста")
        }
        return image
    }

    /// Лист с крупной надписью. Нужен, чтобы проверять распознавание
    /// на настоящем Vision, а не на подставном ответе.
    static func text(_ string: String, width: Int = 1000, height: Int = 400, nearTop: Bool = false) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
        guard let context else {
            preconditionFailure("не удалось создать контекст рисования для теста")
        }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let font = CTFontCreateWithName("Helvetica" as CFString, CGFloat(height) / 3, nil)
        let attributed = NSAttributedString(
            string: string,
            attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font,
                kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            ]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        // Начало координат контекста внизу, поэтому «ближе к верху листа» —
        // это большее значение y.
        let baseline = nearTop ? CGFloat(height) * 0.72 : CGFloat(height) * 0.12
        context.textPosition = CGPoint(x: CGFloat(width) / 12, y: baseline)
        CTLineDraw(line, context)

        guard let image = context.makeImage() else {
            preconditionFailure("не удалось получить изображение из контекста")
        }
        return image
    }
}
