import CoreGraphics
import Foundation
import Testing
@testable import Leaf

@Suite("Подгон файла под заданный вес")
struct SizeFitterTests {
    private func makePages(_ count: Int) -> [Page] {
        (0..<count).map { Page(id: PageID(), order: $0, look: .asShot) }
    }

    @Test("итоговый файл укладывается в предел даже когда без подгона не влезает")
    func resultFitsWithinLimit() async throws {
        // Страницы с рябью сжимаются плохо: без подгона такой файл заведомо
        // тяжелее предела, и проверка отличает работу подбора от совпадения.
        let pages = makePages(3)
        let source = CountingImageSource(size: (1400, 1800), pages: pages, allDetailed: true)
        let fitter = SizeFitter(source: source)

        let outcome = try await fitter.fit(pages: pages, text: [:], limitBytes: 300_000, look: .color)

        guard case let .fitted(result) = outcome else {
            Issue.record("ожидался подобранный файл, пришло \(outcome)")
            return
        }
        #expect(result.bytes <= 300_000)
        #expect(result.data.isEmpty == false)
        #expect(result.plan.scale < 1.0, "подбор обязан был уменьшить страницы")
    }

    @Test("обещанный вес совпадает с весом настоящего файла, а не с оценкой")
    func promisedSizeMatchesTheRealFile() async throws {
        let pages = makePages(2)
        let source = CountingImageSource(size: (1600, 2000), pages: pages, allDetailed: true)
        let fitter = SizeFitter(source: source)

        let outcome = try await fitter.fit(pages: pages, text: [:], limitBytes: 250_000, look: .color)

        guard case let .fitted(result) = outcome else {
            Issue.record("ожидался подобранный файл, пришло \(outcome)")
            return
        }
        #expect(result.bytes == result.data.count)
        #expect(result.data.count <= 250_000)
    }

    @Test("оригиналы читаются по одному разу на страницу, а не на каждое измерение")
    func originalsAreReadOncePerPageNotPerMeasurement() async throws {
        let pages = makePages(4)
        let source = CountingImageSource(size: (1200, 1600), pages: pages)
        let fitter = SizeFitter(source: source)

        _ = try await fitter.fit(pages: pages, text: [:], limitBytes: 200_000, look: .color)

        #expect(source.loadCount == pages.count)
    }

    @Test("щедрый предел не заставляет отдавать качество")
    func generousLimitKeepsFullQuality() async throws {
        let pages = makePages(1)
        let source = CountingImageSource(size: (800, 1000), pages: pages)
        let fitter = SizeFitter(source: source)

        let outcome = try await fitter.fit(pages: pages, text: [:], limitBytes: 50_000_000, look: .color)

        guard case let .fitted(result) = outcome else {
            Issue.record("ожидался подобранный файл, пришло \(outcome)")
            return
        }
        #expect(result.plan.quality == 1.0)
        #expect(result.plan.scale == 1.0)
    }

    @Test("недостижимый предел в цвете заканчивается предложением, а не тупиком")
    func unreachableLimitEndsWithSuggestion() async throws {
        let pages = makePages(6)
        let source = CountingImageSource(size: (3000, 4000), pages: pages)
        let fitter = SizeFitter(source: source)

        let outcome = try await fitter.fit(pages: pages, text: [:], limitBytes: 900, look: .color)

        guard case let .needsLighterLook(suggestion) = outcome else {
            Issue.record("ожидалось предложение сменить режим, пришло \(outcome)")
            return
        }
        #expect(suggestion == .gray)
    }

    @Test("вранью оценки не дают дойти до человека: итог перепроверяется")
    func wrongEstimateIsCaughtBeforeItReachesThePerson() async throws {
        // Мелкая проба оценивает вес заведомо неточно. Если бы приложение
        // верило оценке, оно отдало бы файл тяжелее обещанного.
        let pages = makePages(2)
        let source = CountingImageSource(size: (1600, 2000), pages: pages, allDetailed: true)
        let fitter = SizeFitter(source: source, probeLongSide: 48)

        let outcome = try await fitter.fit(pages: pages, text: [:], limitBytes: 220_000, look: .color)

        // Требуется именно подобранный файл: предел достижим, и отказ здесь
        // означал бы, что приложение сдалось из-за собственной неточности,
        // а не из-за требований человека.
        guard case let .fitted(result) = outcome else {
            Issue.record("оценка разошлась с настоящим весом и подбор сдался: \(outcome)")
            return
        }
        #expect(result.data.count <= 220_000)
    }

    @Test("самая тяжёлая страница названа — человеку есть что с ней сделать")
    func heaviestPageIsNamed() async throws {
        let pages = makePages(3)
        // Вторая страница подробнее остальных, значит и весит больше.
        let source = CountingImageSource(size: (1000, 1000), pages: pages, detailedPageIndex: 1)
        let fitter = SizeFitter(source: source)

        let outcome = try await fitter.fit(pages: pages, text: [:], limitBytes: 400_000, look: .color)

        guard case let .fitted(result) = outcome else {
            Issue.record("ожидался подобранный файл, пришло \(outcome)")
            return
        }
        #expect(result.heaviestPageID == pages[1].id)
    }

    @Test("пустой список страниц даёт ошибку, а не пустой файл")
    func emptyPageListGivesError() async throws {
        let fitter = SizeFitter(source: CountingImageSource(size: (10, 10), pages: []))

        await #expect(throws: PDFBuildError.self) {
            _ = try await fitter.fit(pages: [], text: [:], limitBytes: 1000, look: .color)
        }
    }
}

/// Источник изображений, считающий обращения. Нужен, чтобы доказать: подбор
/// не перечитывает оригиналы на каждое измерение — именно на этом медленны
/// приложения, которые сжимают файл целиком раз за разом.
private final class CountingImageSource: PageImageSource, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let images: [PageID: CGImage]

    init(
        size: (width: Int, height: Int),
        pages: [Page],
        detailedPageIndex: Int? = nil,
        allDetailed: Bool = false
    ) {
        var prepared: [PageID: CGImage] = [:]
        for (index, page) in pages.enumerated() {
            prepared[page.id] = allDetailed || index == detailedPageIndex
                ? ImageFactory.noisy(width: size.width, height: size.height)
                : ImageFactory.halves(width: size.width, height: size.height)
        }
        self.images = prepared
    }

    var loadCount: Int {
        lock.withLock { count }
    }

    func image(for id: PageID) async throws -> CGImage {
        lock.withLock { count += 1 }

        guard let image = images[id] else { throw PageStoreError.pageNotFound(id) }
        return image
    }
}
