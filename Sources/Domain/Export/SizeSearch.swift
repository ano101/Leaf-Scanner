/// Подбор параметров сжатия под заданный вес файла.
///
/// Наивный способ — сжимать готовый файл целиком и повторять — стоит секунд
/// на каждой попытке. Здесь измеритель работает на уменьшенных копиях,
/// а число измерений ограничено: точность в байтах никому не нужна,
/// нужен файл, который влезает.
public enum SizeSearch {
    public static let maxMeasurements = 6

    /// Единственная ручка подбора: 0 — максимальное сжатие, 1 — нетронутый файл.
    /// Качество и масштаб растут вместе с ней, поэтому вес монотонен
    /// и двоичный поиск применим.
    private static func plan(at knob: Double, colorMode: ColorMode) -> ExportPlan {
        ExportPlan(
            quality: 0.2 + 0.8 * knob,
            scale: 0.35 + 0.65 * knob,
            colorMode: colorMode
        )
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
