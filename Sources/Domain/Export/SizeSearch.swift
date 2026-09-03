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
    private static func plan(at knob: Double, colorMode: ColorMode) -> ExportPlan {
        ExportPlan(
            quality: 0.1 + 0.9 * knob,
            scale: 0.15 + 0.85 * knob,
            colorMode: colorMode
        )
    }

    /// Самый сжатый вариант из возможных. Нужен как последняя попытка,
    /// когда оценка по пробам разошлась с настоящим весом.
    public static func smallestPlan(colorMode: ColorMode) -> ExportPlan {
        plan(at: 0.0, colorMode: colorMode)
    }

    public static func fit(
        limitBytes: Int,
        colorMode: ColorMode,
        measure: (ExportPlan) -> Int
    ) -> SizeSearchResult {
        var measurementsLeft = maxMeasurements

        let untouched = plan(at: 1.0, colorMode: colorMode)
        let untouchedBytes = measure(untouched)
        measurementsLeft -= 1
        if untouchedBytes <= limitBytes {
            return .fitted(untouched, bytes: untouchedBytes)
        }

        let smallest = plan(at: 0.0, colorMode: colorMode)
        let smallestBytes = measure(smallest)
        measurementsLeft -= 1
        guard smallestBytes <= limitBytes else {
            if let weaker = colorMode.weaker {
                return .needsWeakerColor(suggestion: weaker)
            }
            return .impossible(bestBytes: smallestBytes)
        }

        var low = 0.0
        var lowBytes = smallestBytes
        var high = 1.0

        while measurementsLeft > 0 {
            let middle = (low + high) / 2
            let candidate = plan(at: middle, colorMode: colorMode)
            let bytes = measure(candidate)
            measurementsLeft -= 1

            if bytes <= limitBytes {
                low = middle
                lowBytes = bytes
            } else {
                high = middle
            }
        }

        return .fitted(plan(at: low, colorMode: colorMode), bytes: lowBytes)
    }
}
