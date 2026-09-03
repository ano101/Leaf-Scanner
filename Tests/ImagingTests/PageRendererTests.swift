import CoreGraphics
import Testing
@testable import Leaf

@Suite("Рендер страницы")
struct PageRendererTests {
    private let renderer = PageRenderer()

    private func page(rotation: Rotation = .none, filter: PageFilter = .original) -> Page {
        Page(id: PageID(), order: 0, rotation: rotation, filter: filter)
    }

    @Test("боковой поворот меняет ширину и высоту местами")
    func sideRotationSwapsDimensions() throws {
        let source = ImageFactory.solid(width: 400, height: 200)
        let result = try renderer.render(source, page: page(rotation: .right), colorMode: .color, scale: 1.0)

        #expect(result.width == 200)
        #expect(result.height == 400)
    }

    @Test("поворот вверх ногами сохраняет размеры")
    func upsideDownKeepsDimensions() throws {
        let source = ImageFactory.solid(width: 400, height: 200)
        let result = try renderer.render(source, page: page(rotation: .upsideDown), colorMode: .color, scale: 1.0)

        #expect(result.width == 400)
        #expect(result.height == 200)
    }

    @Test("поворот действительно переставляет содержимое, а не только рамку")
    func rotationMovesContentNotJustTheFrame() throws {
        // Верхняя половина чёрная, нижняя белая. После поворота вверх ногами
        // яркая половина обязана оказаться сверху.
        let source = ImageFactory.halves(width: 100, height: 100)
        let result = try renderer.render(source, page: page(rotation: .upsideDown), colorMode: .color, scale: 1.0)

        let sourceTop = PixelSampler.averageLuminance(of: try crop(source, topHalf: true))
        let resultTop = PixelSampler.averageLuminance(of: try crop(result, topHalf: true))

        #expect(abs(sourceTop - resultTop) > 100)
    }

    @Test("масштаб уменьшает страницу в заданную долю")
    func scaleShrinksPage() throws {
        let source = ImageFactory.solid(width: 1000, height: 800)
        let result = try renderer.render(source, page: page(), colorMode: .color, scale: 0.5)

        #expect(result.width == 500)
        #expect(result.height == 400)
    }

    @Test("масштаб не увеличивает страницу сверх оригинала")
    func scaleNeverEnlargesBeyondOriginal() throws {
        let source = ImageFactory.solid(width: 300, height: 300)
        let result = try renderer.render(source, page: page(), colorMode: .color, scale: 2.0)

        #expect(result.width == 300)
        #expect(result.height == 300)
    }

    @Test("чёрно-белый режим оставляет не больше двух уровней яркости")
    func blackAndWhiteLeavesAtMostTwoLevels() throws {
        let source = ImageFactory.halves(width: 120, height: 120)
        let result = try renderer.render(source, page: page(), colorMode: .blackAndWhite, scale: 1.0)

        #expect(PixelSampler.luminanceLevels(of: result).count <= 2)
    }

    @Test("серый режим убирает цвет, но сохраняет полутона")
    func grayRemovesColorButKeepsShades() throws {
        let source = ImageFactory.halves(width: 120, height: 120)
        let result = try renderer.render(source, page: page(), colorMode: .gray, scale: 1.0)

        #expect(PixelSampler.luminanceLevels(of: result).count >= 2)
    }

    @Test("обрезка нижней половины оставляет светлую часть")
    func croppingBottomHalfKeepsTheLightPart() throws {
        let source = ImageFactory.halves(width: 200, height: 200)
        var cropped = page()
        cropped.crop = NormalizedQuad(
            topLeft: NormalizedPoint(x: 0, y: 0.5),
            topRight: NormalizedPoint(x: 1, y: 0.5),
            bottomRight: NormalizedPoint(x: 1, y: 1),
            bottomLeft: NormalizedPoint(x: 0, y: 1)
        )

        let result = try renderer.render(source, page: cropped, colorMode: .color, scale: 1.0)

        #expect(result.height < source.height)
        #expect(PixelSampler.averageLuminance(of: result) > 200)
    }

    private func crop(_ image: CGImage, topHalf: Bool) throws -> CGImage {
        let height = image.height / 2
        let rect = CGRect(x: 0, y: topHalf ? 0 : height, width: image.width, height: height)
        guard let cropped = image.cropping(to: rect) else {
            throw PageRenderError.renderFailed
        }
        return cropped
    }
}
