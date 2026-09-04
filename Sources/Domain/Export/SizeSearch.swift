/// Подбор параметров сжатия под заданный вес файла.
///
/// Наивный способ — сжимать готовый файл целиком и повторять — стоит секунд
/// на каждой попытке. Здесь измеритель работает на уменьшенных копиях,
/// а число измерений ограничено: точность в байтах никому не нужна,
/// нужен файл, который влезает.
public enum SizeSearch {
    public static let maxMeasurements = 6

    /// Единственная ручка подбора: 0 — максимальное сжатие, 1 — нетронутый файл.
    ///
    /// Нижняя граница выбрана низкой нарочно: документ, ужатый до нечитаемости,
    /// человек хотя бы увидит и переспросит, а недостижимый предел не оставляет
    /// ему вообще ничего.
    /// Качество и масштаб растут вместе с ней, поэтому вес монотонен
    /// и двоичный поиск применим.
    private static func plan(at knob: Double, look: PageLook) -> ExportPlan {
        ExportPlan(
            quality: 0.1 + 0.9 * knob,
            scale: 0.15 + 0.85 * knob,
            look: look
        )
    }

    /// Самый сжатый вариант из возможных. Нужен как последняя попытка,
    /// когда оценка по пробам разошлась с настоящим весом.
    public static func smallestPlan(look: PageLook) -> ExportPlan {
        plan(at: 0.0, look: look)
    }

    public static func fit(
        limitBytes: Int,
        look: PageLook,
        measure: (ExportPlan) -> Int
    ) -> SizeSearchResult {
        var measurementsLeft = maxMeasurements

        let untouched = plan(at: 1.0, look: look)
        let untouchedBytes = measure(untouched)
        measurementsLeft -= 1
        if untouchedBytes <= limitBytes {
            return .fitted(untouched, bytes: untouchedBytes)
        }

        let smallest = plan(at: 0.0, look: look)
        let smallestBytes = measure(smallest)
        measurementsLeft -= 1
        guard smallestBytes <= limitBytes else {
            if let lighter = look.lighter {
                return .needsLighterLook(suggestion: lighter)
            }
            return .impossible(bestBytes: smallestBytes)
        }

        var low = 0.0
        var lowBytes = smallestBytes
        var high = 1.0

        while measurementsLeft > 0 {
            let middle = (low + high) / 2
            let candidate = plan(at: middle, look: look)
            let bytes = measure(candidate)
            measurementsLeft -= 1

            if bytes <= limitBytes {
                low = middle
                lowBytes = bytes
            } else {
                high = middle
            }
        }

        return .fitted(plan(at: low, look: look), bytes: lowBytes)
    }
}
