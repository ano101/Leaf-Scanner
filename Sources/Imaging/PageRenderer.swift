import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

public enum PageRenderError: Error, Equatable, Sendable {
    case renderFailed
}

/// Превращает исходный кадр в то, что человек увидит и отправит.
///
/// Порядок действий не произвольный: сначала обрезка по углам листа, потом
/// обработка цвета, потом поворот, и только в конце масштаб. Обратный порядок
/// заставил бы обрабатывать пиксели, которые всё равно будут выброшены.
///
/// CIContext создаётся один раз: его пересоздание на каждый кадр — самая
/// частая причина медленного рендера в приложениях на Core Image.
public final class PageRenderer: @unchecked Sendable {
    private let context: CIContext

    public init() {
        // Контекст Core Image потокобезопасен по документации Apple,
        // поэтому один экземпляр обслуживает все обращения.
        self.context = CIContext(options: [.useSoftwareRenderer: false])
    }

    public func render(
        _ image: CGImage,
        page: Page,
        colorMode: ColorMode,
        scale: Double
    ) throws -> CGImage {
        var picture = CIImage(cgImage: image)

        if let crop = page.crop, crop != .full {
            picture = corrected(picture, by: crop, in: image)
        }

        if page.filter == .enhanced {
            picture = enhanced(picture)
        }

        picture = colored(picture, mode: colorMode)
        picture = redacted(picture, areas: page.redactions)
        picture = rotated(picture, by: page.rotation)

        // Увеличивать нечего: пикселей больше, чем снято, не станет,
        // а вес файла вырастет впустую.
        let effectiveScale = min(max(scale, 0.05), 1.0)
        if effectiveScale < 1.0 {
            picture = scaled(picture, by: effectiveScale)
        }

        guard let result = context.createCGImage(picture, from: picture.extent) else {
            throw PageRenderError.renderFailed
        }
        return result
    }

    /// Уничтожение замазанных областей происходит здесь, а не поверх готового
    /// изображения: закрашенные пиксели не существуют уже в результате рендера.
    private func redacted(_ picture: CIImage, areas: [RedactionArea]) -> CIImage {
        guard areas.isEmpty == false else { return picture }

        let extent = picture.extent
        var result = picture

        for area in areas {
            let rect = CGRect(
                x: extent.minX + area.rect.x * extent.width,
                // Начало координат Core Image внизу, а доли считаются сверху.
                y: extent.minY + (1 - area.rect.maxY) * extent.height,
                width: area.rect.width * extent.width,
                height: area.rect.height * extent.height
            )

            let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: rect)
            result = black.composited(over: result)
        }

        return result
    }

    private func corrected(_ picture: CIImage, by quad: NormalizedQuad, in image: CGImage) -> CIImage {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)

        func point(_ normalized: NormalizedPoint) -> CGPoint {
            // Доли отсчитываются сверху, Core Image — снизу.
            CGPoint(x: CGFloat(normalized.x) * width, y: (1 - CGFloat(normalized.y)) * height)
        }

        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = picture
        filter.topLeft = point(quad.topLeft)
        filter.topRight = point(quad.topRight)
        filter.bottomRight = point(quad.bottomRight)
        filter.bottomLeft = point(quad.bottomLeft)
        filter.crop = true

        return filter.outputImage ?? picture
    }

    private func enhanced(_ picture: CIImage) -> CIImage {
        let filter = CIFilter.documentEnhancer()
        filter.inputImage = picture
        filter.amount = 1.0
        return filter.outputImage ?? picture
    }

    private func colored(_ picture: CIImage, mode: ColorMode) -> CIImage {
        switch mode {
        case .color:
            return picture
        case .gray:
            let filter = CIFilter.colorControls()
            filter.inputImage = picture
            filter.saturation = 0
            return filter.outputImage ?? picture
        case .blackAndWhite:
            let mono = CIFilter.colorControls()
            mono.inputImage = picture
            mono.saturation = 0
            guard let grayscale = mono.outputImage else { return picture }

            let threshold = CIFilter.colorThreshold()
            threshold.inputImage = grayscale
            threshold.threshold = 0.5
            return threshold.outputImage ?? grayscale
        }
    }

    private func rotated(_ picture: CIImage, by rotation: Rotation) -> CIImage {
        guard rotation != .none else { return picture }

        let radians = -CGFloat(rotation.rawValue) * .pi / 180
        let rotated = picture.transformed(by: CGAffineTransform(rotationAngle: radians))

        // После поворота начало координат уезжает в минус; изображение
        // возвращается в первый квадрант, иначе экстент будет отрицательным.
        return rotated.transformed(
            by: CGAffineTransform(translationX: -rotated.extent.minX, y: -rotated.extent.minY)
        )
    }

    private func scaled(_ picture: CIImage, by factor: Double) -> CIImage {
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = picture
        filter.scale = Float(factor)
        filter.aspectRatio = 1
        return filter.outputImage ?? picture
    }
}
