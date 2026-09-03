import Foundation
import Testing
@testable import Leaf

@Suite("Подбор под целевой вес")
struct SizeSearchTests {
    /// Вес растёт линейно с качеством и масштабом: этого достаточно,
    /// чтобы проверить сам поиск, не трогая ни одного файла на диске.
    private func linearMeasure(fullWeight: Int) -> @Sendable (ExportPlan) -> Int {
        { plan in Int(Double(fullWeight) * plan.quality * plan.scale) }
    }

    @Test("найденный план укладывается в лимит")
    func foundPlanFitsWithinLimit() {
        let result = SizeSearch.fit(
            limitBytes: 1_000_000,
            colorMode: .color,
            measure: linearMeasure(fullWeight: 10_000_000)
        )

        guard case let .fitted(_, bytes) = result else {
            Issue.record("ожидался подобранный план, пришло \(result)")
            return
        }
        #expect(bytes <= 1_000_000)
    }

    @Test("подбор не отдаёт качество ниже необходимого")
    func searchDoesNotGiveAwayMoreQualityThanNeeded() {
        let result = SizeSearch.fit(
            limitBytes: 5_000_000,
            colorMode: .color,
            measure: linearMeasure(fullWeight: 10_000_000)
        )

        guard case let .fitted(plan, bytes) = result else {
            Issue.record("ожидался подобранный план, пришло \(result)")
            return
        }
        #expect(bytes <= 5_000_000)
        // Половина лимита означала бы, что качество отдано зря.
        #expect(bytes > 2_500_000)
        #expect(plan.colorMode == .color)
    }

    @Test("файл, влезающий без сжатия, отдаётся нетронутым")
    func fileThatAlreadyFitsIsLeftUntouched() {
        let result = SizeSearch.fit(limitBytes: 10_000_000, colorMode: .color) { _ in 900_000 }

        guard case let .fitted(plan, _) = result else {
            Issue.record("ожидался подобранный план, пришло \(result)")
            return
        }
        #expect(plan.quality == 1.0)
        #expect(plan.scale == 1.0)
    }

    @Test("недостижимый лимит в цвете предлагает серый, а не тупик")
    func unreachableLimitInColorSuggestsGray() {
        let result = SizeSearch.fit(limitBytes: 500_000, colorMode: .color) { _ in 9_000_000 }
        #expect(result == .needsWeakerColor(suggestion: .gray))
    }

    @Test("недостижимый лимит в сером предлагает чёрно-белый")
    func unreachableLimitInGraySuggestsBlackAndWhite() {
        let result = SizeSearch.fit(limitBytes: 500_000, colorMode: .gray) { _ in 9_000_000 }
        #expect(result == .needsWeakerColor(suggestion: .blackAndWhite))
    }

    @Test("в чёрно-белом предлагать больше нечего — честный отказ с лучшим весом")
    func blackAndWhiteHasNothingWeakerToSuggest() {
        let result = SizeSearch.fit(limitBytes: 500_000, colorMode: .blackAndWhite) { _ in 9_000_000 }
        #expect(result == .impossible(bestBytes: 9_000_000))
    }

    @Test("поиск делает не больше шести измерений")
    func searchStaysWithinSixMeasurements() {
        let counter = MeasurementCounter()
        _ = SizeSearch.fit(limitBytes: 1_000_000, colorMode: .color) { plan in
            counter.increment()
            return Int(10_000_000 * plan.quality * plan.scale)
        }

        #expect(counter.value <= SizeSearch.maxMeasurements)
        #expect(SizeSearch.maxMeasurements == 6)
    }

    @Test("нулевой лимит не зацикливает поиск")
    func zeroLimitDoesNotLoopForever() {
        let counter = MeasurementCounter()
        let result = SizeSearch.fit(limitBytes: 0, colorMode: .blackAndWhite) { plan in
            counter.increment()
            return Int(10_000_000 * plan.quality * plan.scale)
        }

        #expect(counter.value <= SizeSearch.maxMeasurements)
        if case .fitted = result {
            Issue.record("нулевой лимит не может быть достигнут")
        }
    }
}

/// Счётчик обращений к измерителю. Отдельный класс, потому что замыкание
/// помечено Sendable и захватить переменную по ссылке иначе нельзя.
private final class MeasurementCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
