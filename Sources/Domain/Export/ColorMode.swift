/// Цветовой режим итогового файла. Порядок перечисления — от тяжёлого
/// к лёгкому: следующий режим всегда весит меньше предыдущего.
public enum ColorMode: String, Sendable, Codable, CaseIterable {
    case color
    case gray
    case blackAndWhite

    /// Следующий режим, который весит меньше. Нужен, чтобы недостижимый
    /// предел веса заканчивался предложением, а не отказом.
    public var weaker: ColorMode? {
        switch self {
        case .color: .gray
        case .gray: .blackAndWhite
        case .blackAndWhite: nil
        }
    }

    public var titleKey: String { "export.color.\(rawValue)" }
}
