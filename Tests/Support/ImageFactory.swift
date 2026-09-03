import CoreGraphics
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
}
