import CoreGraphics
import Foundation

/// Отпечаток изображения, устойчивый к освещению и мелким сдвигам.
///
/// Считается разностный хеш: изображение сжимается до девяти на восемь точек
/// серого, и каждый разряд отвечает на вопрос «следующая точка светлее
/// предыдущей». Ответ не зависит от общей яркости — поэтому тот же лист,
/// снятый у окна и под лампой, даёт близкие отпечатки.
public enum PerceptualHash {
    private static let side = 8

    /// Порог, до которого страницы считаются одним и тем же листом.
    /// Выбран с запасом: ложный вопрос «это повтор?» стоит человеку одного
    /// касания, а пропущенный дубликат — лишней страницы в документе.
    public static let duplicateThreshold = 10

    public static func hash(_ image: CGImage) -> UInt64 {
        let width = side + 1
        let height = side
        var pixels = [UInt8](repeating: 0, count: width * height)

        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }

            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        var result: UInt64 = 0
        var bit = 0

        for row in 0..<height {
            for column in 0..<side {
                let left = pixels[row * width + column]
                let right = pixels[row * width + column + 1]
                if right > left {
                    result |= (1 << UInt64(bit))
                }
                bit += 1
            }
        }

        return result
    }

    /// Расстояние Хэмминга: сколько разрядов различаются.
    public static func distance(_ first: UInt64, _ second: UInt64) -> Int {
        (first ^ second).nonzeroBitCount
    }
}
