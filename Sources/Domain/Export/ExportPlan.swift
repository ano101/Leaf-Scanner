/// Набор параметров, которым собирается итоговый файл.
public struct ExportPlan: Equatable, Sendable {
    public let quality: Double
    public let scale: Double
    public let look: PageLook

    public init(quality: Double, scale: Double, look: PageLook) {
        self.quality = quality
        self.scale = scale
        self.look = look
    }

    public static func best(look: PageLook) -> ExportPlan {
        ExportPlan(quality: 1.0, scale: 1.0, look: look)
    }
}

public enum SizeSearchResult: Equatable, Sendable {
    /// Параметры найдены, файл такого веса получится.
    case fitted(ExportPlan, bytes: Int)
    /// В этом виде предел недостижим, но есть более лёгкий вид.
    case needsLighterLook(suggestion: PageLook)
    /// Легче уже некуда. Показывается достижимый вес, а не пустой отказ.
    case impossible(bestBytes: Int)
}
