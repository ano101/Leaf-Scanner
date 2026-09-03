import CoreGraphics
import Testing
@testable import Leaf

@Suite("Перцептивный хеш и повторные сканы")
struct PerceptualHashTests {
    @Test("одно и то же изображение даёт один и тот же хеш")
    func sameImageGivesSameHash() {
        let image = ImageFactory.gradient(width: 400, height: 300)

        #expect(PerceptualHash.hash(image) == PerceptualHash.hash(image))
    }

    @Test("тот же лист при другом освещении остаётся тем же листом")
    func sameSheetUnderDifferentLightIsStillTheSameSheet() {
        let bright = PerceptualHash.hash(ImageFactory.gradient(width: 400, height: 300, brightness: 1.0))
        let dim = PerceptualHash.hash(ImageFactory.gradient(width: 400, height: 300, brightness: 0.6))

        #expect(PerceptualHash.distance(bright, dim) <= PerceptualHash.duplicateThreshold)
    }

    @Test("другой лист не выдаётся за повтор")
    func differentSheetIsNotPassedOffAsDuplicate() {
        let gradient = PerceptualHash.hash(ImageFactory.gradient(width: 400, height: 300))
        let halves = PerceptualHash.hash(ImageFactory.halves(width: 400, height: 300))

        #expect(PerceptualHash.distance(gradient, halves) > PerceptualHash.duplicateThreshold)
    }

    @Test("расстояние до самого себя равно нулю")
    func distanceToItselfIsZero() {
        #expect(PerceptualHash.distance(0xABCD_1234_5678_9EF0, 0xABCD_1234_5678_9EF0) == 0)
    }

    @Test("расстояние считает именно разряды, а не разность чисел")
    func distanceCountsBitsNotNumericDifference() {
        #expect(PerceptualHash.distance(0b0000, 0b1111) == 4)
        #expect(PerceptualHash.distance(0, UInt64.max) == 64)
    }
}

@Suite("Поиск повторов в архиве")
struct DuplicateFinderTests {
    private func page(hash: UInt64?) -> Page {
        var page = PageFactory.page()
        page.perceptualHash = hash
        return page
    }

    @Test("близкая страница находится")
    func nearPageIsFound() {
        let existing = page(hash: 0b1111_0000)
        let found = DuplicateFinder.near(0b1111_0001, in: [existing])

        #expect(found.count == 1)
        #expect(found.first == existing.id)
    }

    @Test("далёкая страница не находится")
    func farPageIsNotFound() {
        let found = DuplicateFinder.near(UInt64.max, in: [page(hash: 0)])

        #expect(found.isEmpty)
    }

    @Test("страницы без хеша пропускаются, а не считаются совпадением")
    func pagesWithoutHashAreSkipped() {
        #expect(DuplicateFinder.near(0, in: [page(hash: nil)]).isEmpty)
    }

    @Test("пустой архив не даёт находок")
    func emptyArchiveGivesNothing() {
        #expect(DuplicateFinder.near(0, in: []).isEmpty)
    }

    @Test("находки идут от самой похожей к менее похожей")
    func matchesComeFromClosestToFurthest() {
        let closest = page(hash: 0b1111_0000)
        let further = page(hash: 0b1111_0011)
        let found = DuplicateFinder.near(0b1111_0000, in: [further, closest])

        #expect(found.count == 2)
        #expect(found.first == closest.id)
    }
}
