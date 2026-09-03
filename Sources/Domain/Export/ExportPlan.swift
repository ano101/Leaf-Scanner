/// Набор параметров, которым собирается итоговый файл.
public struct ExportPlan: Equatable, Sendable {
    public let quality: Double
    public let scale: Double
    public let colorMode: ColorMode

    public init(quality: Double, scale: Double, colorMode: ColorMode) {
        self.quality = quality
        self.scale = scale
        self.colorMode = colorMode
    }

    public static func best(colorMode: ColorMode) -> ExportPlan {
        ExportPlan(quality: 1.0, scale: 1.0, colorMode: colorMode)
    }
}

public enum SizeSearchResult: Equatable, Sendable {
    /// Параметры найдены, файл такого веса получится.
    case fitted(ExportPlan, bytes: Int)
    /// В этом цветовом режиме предел недостижим, но есть более лёгкий режим.
    case needsWeakerColor(suggestion: ColorMode)
    /// Легче уже некуда. Показывается достижимый вес, а не пустой отказ.
    case impossible(bestBytes: Int)
}
