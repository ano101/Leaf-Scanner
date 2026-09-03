import CoreGraphics
import Foundation

/// Чтение пикселей результата. Проверять рендер по «выглядит правильно»
/// нельзя — проверяются числа.
enum PixelSampler {
    /// Все различающиеся уровни яркости в изображении.
    static func luminanceLevels(of image: CGImage) -> Set<Int> {
        Set(luminances(of: image))
    }

    static func averageLuminance(of image: CGImage) -> Double {
        let values = luminances(of: image)
        guard values.isEmpty == false else { return 0 }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    private static func luminances(of image: CGImage) -> [Int] {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        return stride(from: 0, to: pixels.count, by: 4).map { index in
            let red = Double(pixels[index])
            let green = Double(pixels[index + 1])
            let blue = Double(pixels[index + 2])
            return Int((0.299 * red + 0.587 * green + 0.114 * blue).rounded())
        }
    }
}
