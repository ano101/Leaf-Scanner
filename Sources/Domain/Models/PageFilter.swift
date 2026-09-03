/// Как страница выглядит после обработки. Чёрно-белый режим выбран не только
/// ради вида: он резко уменьшает вес файла, и это его вторая работа.
public enum PageFilter: String, Sendable, Codable, CaseIterable {
    case original
    case enhanced
    case gray
    case blackAndWhite
}
