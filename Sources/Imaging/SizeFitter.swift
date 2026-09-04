import CoreGraphics
import Foundation

public protocol PageImageSource: Sendable {
    func image(for id: PageID) async throws -> CGImage
}

public struct SizeFitResult: Sendable {
    public let data: Data
    public let plan: ExportPlan
    public let bytes: Int
    /// Самая тяжёлая страница. Человеку нужно не только «не влезает»,
    /// но и что именно с этим делать.
    public let heaviestPageID: PageID?
}

public enum SizeFitOutcome: Sendable {
    case fitted(SizeFitResult)
    case needsLighterLook(suggestion: PageLook)
    case impossible(bestBytes: Int)
}

/// Подгон готового файла под заданный вес.
///
/// Измерения идут на уменьшенных копиях страниц, а не на полном разрешении:
/// каждая проба стоит миллисекунды вместо секунд. В полном размере
/// собирается только выбранный вариант.
public struct SizeFitter: Sendable {
    /// Длинная сторона пробной копии. Меньше — быстрее, но оценка веса
    /// начинает врать; на этом размере отношение весов уже устойчиво.
    ///
    /// Задаётся снаружи, чтобы проверку страховки можно было поставить
    /// в заведомо плохие условия: со слишком мелкой пробой оценка обязана
    /// разойтись с настоящим весом, и тогда видно, работает ли перепроверка.
    public static let defaultProbeLongSide = 700

    private let source: any PageImageSource
    private let renderer: PageRenderer
    private let builder: PDFBuilder
    private let probeLongSide: Int

    public init(
        source: any PageImageSource,
        renderer: PageRenderer = PageRenderer(),
        builder: PDFBuilder = PDFBuilder(),
        probeLongSide: Int = SizeFitter.defaultProbeLongSide
    ) {
        self.source = source
        self.renderer = renderer
        self.builder = builder
        self.probeLongSide = probeLongSide
    }

    public func fit(
        pages: [Page],
        text: [PageID: [RecognizedLine]],
        limitBytes: Int,
        look: PageLook,
        password: String? = nil
    ) async throws -> SizeFitOutcome {
        guard pages.isEmpty == false else { throw PDFBuildError.noPages }

        // Оригиналы читаются ровно по разу: дальше работа идёт с копиями
        // в памяти, сколько бы измерений ни потребовалось.
        var originals: [PageID: CGImage] = [:]
        var probes: [PageID: CGImage] = [:]
        var fullPixels = 0.0
        var probePixels = 0.0

        for page in pages {
            let original = try await source.image(for: page.id)
            originals[page.id] = original

            let probe = downscaled(original, longSide: probeLongSide)
            probes[page.id] = probe

            fullPixels += Double(original.width * original.height)
            probePixels += Double(probe.width * probe.height)
        }

        let ratio = probePixels > 0 ? fullPixels / probePixels : 1.0

        let outcome = SizeSearch.fit(limitBytes: limitBytes, look: look) { plan in
            let bytes = (try? measure(pages: pages, images: probes, text: text, plan: plan)) ?? Int.max
            return bytes == Int.max ? Int.max : Int(Double(bytes) * ratio)
        }

        switch outcome {
        case .needsLighterLook(let suggestion):
            // Отказ по оценке — ещё не отказ. Оценка строится на уменьшенных
            // копиях и может завысить вес; прежде чем сказать человеку «не
            // получится», самый сжатый вариант собирается по-настоящему.
            if let rescued = try rescue(
                pages: pages, images: originals, probes: probes, text: text,
                limitBytes: limitBytes, look: look, password: password
            ) {
                return .fitted(rescued)
            }
            return .needsLighterLook(suggestion: suggestion)

        case .impossible(let bestBytes):
            if let rescued = try rescue(
                pages: pages, images: originals, probes: probes, text: text,
                limitBytes: limitBytes, look: look, password: password
            ) {
                return .fitted(rescued)
            }
            return .impossible(bestBytes: bestBytes)

        case .fitted(let plan, let estimate):
            var chosen = plan
            var data = try build(pages: pages, images: originals, text: text, plan: chosen, password: password)

            // Оценка по пробам могла оказаться оптимистичной. Обещать вес
            // и отдать файл тяжелее обещанного нельзя: человек узнает об этом
            // от почтового ящика, который откажется его принять. Поэтому
            // оценка калибруется настоящим весом и подбор повторяется — но
            // не более одного раза, чтобы ожидание оставалось коротким.
            if data.count > limitBytes {
                let correction = Double(data.count) / Double(max(estimate, 1))
                let calibrated = SizeSearch.fit(limitBytes: limitBytes, look: look) { candidate in
                    let bytes = (try? measure(pages: pages, images: probes, text: text, plan: candidate)) ?? Int.max
                    return bytes == Int.max ? Int.max : Int(Double(bytes) * ratio * correction)
                }

                switch calibrated {
                case .needsLighterLook(let suggestion):
                    return .needsLighterLook(suggestion: suggestion)
                case .impossible(let bestBytes):
                    return .impossible(bestBytes: bestBytes)
                case .fitted(let secondPlan, _):
                    chosen = secondPlan
                    data = try build(pages: pages, images: originals, text: text, plan: chosen, password: password)
                }
            }

            // Последняя попытка: самый сжатый вариант. Оценка по пробам
            // может разойтись с настоящим весом настолько, что подбор
            // остановится раньше времени, — но у самого сжатого плана
            // проверять уже нечего, он либо влезает, либо нет.
            if data.count > limitBytes {
                let smallest = SizeSearch.smallestPlan(look: look)
                let smallestData = try build(pages: pages, images: originals, text: text, plan: smallest, password: password)
                if smallestData.count <= limitBytes {
                    chosen = smallest
                    data = smallestData
                }
            }

            // Даже так предел может остаться недостижимым. Честный отказ
            // с настоящим весом полезнее файла, который не примут.
            guard data.count <= limitBytes else {
                if let lighter = look.lighter {
                    return .needsLighterLook(suggestion: lighter)
                }
                return .impossible(bestBytes: data.count)
            }

            let heaviest = try heaviestPage(pages: pages, images: probes, text: text, plan: chosen)

            return .fitted(SizeFitResult(
                data: data,
                plan: chosen,
                bytes: data.count,
                heaviestPageID: heaviest
            ))
        }
    }

    /// Настоящая сборка самого сжатого варианта. Если он влезает, отказ был
    /// ошибкой оценки, а не требованием человека.
    private func rescue(
        pages: [Page],
        images: [PageID: CGImage],
        probes: [PageID: CGImage],
        text: [PageID: [RecognizedLine]],
        limitBytes: Int,
        look: PageLook,
        password: String?
    ) throws -> SizeFitResult? {
        let smallest = SizeSearch.smallestPlan(look: look)
        let data = try build(pages: pages, images: images, text: text, plan: smallest, password: password)
        guard data.count <= limitBytes else { return nil }

        return SizeFitResult(
            data: data,
            plan: smallest,
            bytes: data.count,
            heaviestPageID: try heaviestPage(pages: pages, images: probes, text: text, plan: smallest)
        )
    }

    private func measure(
        pages: [Page],
        images: [PageID: CGImage],
        text: [PageID: [RecognizedLine]],
        plan: ExportPlan
    ) throws -> Int {
        try build(pages: pages, images: images, text: text, plan: plan).count
    }

    /// Пароль применяется только к настоящим сборкам: пробы существуют ради
    /// скорости, и шифровать их незачем.
    private func build(
        pages: [Page],
        images: [PageID: CGImage],
        text: [PageID: [RecognizedLine]],
        plan: ExportPlan,
        password: String? = nil
    ) throws -> Data {
        let rendered = try PageOrdering.sorted(pages).map { page -> RenderedPage in
            guard let image = images[page.id] else {
                throw PageStoreError.pageNotFound(page.id)
            }
            return RenderedPage(
                image: try renderer.render(image, page: page, look: plan.look, scale: plan.scale),
                text: text[page.id] ?? [],
                redactions: page.redactions
            )
        }

        return try builder.build(pages: rendered, password: password)
    }

    /// Вес считается по пробным копиям: сравнение относительное,
    /// и полное разрешение здесь ничего не уточнит.
    private func heaviestPage(
        pages: [Page],
        images: [PageID: CGImage],
        text: [PageID: [RecognizedLine]],
        plan: ExportPlan
    ) throws -> PageID? {
        var heaviest: (id: PageID, bytes: Int)?

        for page in pages {
            let bytes = try measure(pages: [page], images: images, text: text, plan: plan)
            if heaviest == nil || bytes > heaviest!.bytes {
                heaviest = (page.id, bytes)
            }
        }

        return heaviest?.id
    }

    private func downscaled(_ image: CGImage, longSide: Int) -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > longSide else { return image }

        let factor = Double(longSide) / Double(longest)
        let width = max(1, Int((Double(image.width) * factor).rounded()))
        let height = max(1, Int((Double(image.height) * factor).rounded()))

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return image }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        return context.makeImage() ?? image
    }
}
