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
        look: PageLook,
        scale: Double
    ) throws -> CGImage {
        var picture = CIImage(cgImage: image)

        if let crop = page.crop, crop != .full {
            picture = corrected(picture, by: crop, in: image)
        }

        picture = looked(picture, as: look)
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

    /// Приведение страницы к выбранному виду.
    ///
    /// Порядок важен: сначала выравнивается освещение, и только потом
    /// снимается цвет или ставится порог. Обратный порядок — то, что делает
    /// большинство приложений, — превращает тень от руки в чёрное пятно,
    /// потому что порог один на весь лист.
    private func looked(_ picture: CIImage, as look: PageLook) -> CIImage {
        guard look.flattensLighting else { return picture }

        let flattened = flattenedLighting(picture)

        switch look {
        case .asShot:
            return picture
        case .color:
            return flattened
        case .gray:
            let filter = CIFilter.colorControls()
            filter.inputImage = flattened
            filter.saturation = 0
            return filter.outputImage ?? flattened
        case .blackAndWhite:
            let mono = CIFilter.colorControls()
            mono.inputImage = flattened
            mono.saturation = 0
            guard let grayscale = mono.outputImage else { return flattened }

            let threshold = CIFilter.colorThreshold()
            threshold.inputImage = grayscale
            // После выравнивания бумага везде около единицы, поэтому один
            // порог работает как местный: он сравнивает точку не с абсолютной
            // яркостью, а с яркостью бумаги рядом с ней.
            threshold.threshold = 0.62
            return threshold.outputImage ?? grayscale
        }
    }

    /// Выравнивание освещения — то, чем сканер отличается от фотоаппарата.
    ///
    /// Сильное размытие оставляет от страницы только освещённость: буквы
    /// в нём растворяются, а тень от руки и градиент от лампы остаются.
    /// Деление исходника на эту освещённость убирает их разом — вместе
    /// с желтизной бумаги, потому что делится каждый цветовой канал
    /// по отдельности.
    private func flattenedLighting(_ picture: CIImage) -> CIImage {
        let extent = picture.extent
        guard extent.width > 1, extent.height > 1 else { return picture }

        // Радиус берётся от размера листа: он обязан быть заметно крупнее
        // буквы, иначе размытие сохранит текст и деление его сотрёт.
        let radius = Float(min(extent.width, extent.height) / 12)

        let blur = CIFilter.boxBlur()
        blur.inputImage = picture.clampedToExtent()
        blur.radius = radius
        guard let illumination = blur.outputImage?.cropped(to: extent) else { return picture }

        let divide = CIFilter.divideBlendMode()
        divide.inputImage = illumination
        divide.backgroundImage = picture
        guard let normalized = divide.outputImage else { return picture }

        // После деления бумага выходит около единицы, но текст оказывается
        // бледнее исходного. Подтяжка возвращает ему плотность.
        let contrast = CIFilter.colorControls()
        contrast.inputImage = normalized
        contrast.contrast = 1.35
        contrast.brightness = -0.04

        return contrast.outputImage ?? normalized
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
