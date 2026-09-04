/// Как страница выглядит после обработки. Чёрно-белый режим выбран не только
/// ради вида: он резко уменьшает вес файла, и это его вторая работа.
public enum PageFilter: String, Sendable, Codable, CaseIterable {
    case original
    case enhanced
    case gray
    case blackAndWhite

    /// Ключ перевода отдаётся самим типом.
    ///
    /// Собирать его подстановкой прямо в литерал `LocalizedStringKey`
    /// нельзя: SwiftUI разбирает такой литерал как строку формата и ищет
    /// ключ «filter.%@», которого нет ни в одном каталоге. Надпись
    /// молча остаётся непереведённой.
    public var titleKey: String { "filter.\(rawValue)" }
}
