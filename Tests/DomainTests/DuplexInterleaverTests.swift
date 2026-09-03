import Testing
@testable import Leaf

@Suite("Двусторонняя стопка")
struct DuplexInterleaverTests {
    /// Пачку переворачивают целиком, поэтому первый снятый оборот
    /// принадлежит последнему лицевому листу.
    @Test("обороты снятые с перевёрнутой пачки встают к своим лицевым")
    func backsFromFlippedStackPairWithTheirFronts() {
        let fronts = PageFactory.pages(count: 3)
        let backs = PageFactory.pages(count: 3)

        let result = DuplexInterleaver.interleave(fronts: fronts, backs: backs)

        #expect(result.count == 6)
        #expect(result.map(\.id) == [
            fronts[0].id, backs[2].id,
            fronts[1].id, backs[1].id,
            fronts[2].id, backs[0].id,
        ])
    }

    @Test("страницы результата пронумерованы подряд")
    func resultIsNumberedConsecutively() {
        let result = DuplexInterleaver.interleave(
            fronts: PageFactory.pages(count: 2),
            backs: PageFactory.pages(count: 2)
        )

        #expect(result.map(\.order) == [0, 1, 2, 3])
    }

    @Test("нехватка оборотов оставляет лишние лицевые без пары")
    func missingBacksLeaveFrontsAlone() {
        let fronts = PageFactory.pages(count: 3)
        let backs = PageFactory.pages(count: 1)

        let result = DuplexInterleaver.interleave(fronts: fronts, backs: backs)

        #expect(result.count == 4)
        #expect(result.map(\.id) == [fronts[0].id, fronts[1].id, fronts[2].id, backs[0].id])
    }

    @Test("лишние обороты не теряются, а дописываются в конец")
    func extraBacksAreAppendedRatherThanDropped() {
        let fronts = PageFactory.pages(count: 1)
        let backs = PageFactory.pages(count: 3)

        let result = DuplexInterleaver.interleave(fronts: fronts, backs: backs)

        #expect(result.count == 4)
        #expect(result.first?.id == fronts[0].id)
    }

    @Test("без оборотов документ состоит из одних лицевых")
    func withoutBacksOnlyFrontsRemain() {
        let fronts = PageFactory.pages(count: 2)
        let result = DuplexInterleaver.interleave(fronts: fronts, backs: [])

        #expect(result.count == 2)
        #expect(result.map(\.id) == fronts.map(\.id))
    }

    @Test("пустая съёмка даёт пустой документ")
    func emptyCaptureGivesEmptyDocument() {
        #expect(DuplexInterleaver.interleave(fronts: [], backs: []).isEmpty)
    }
}
