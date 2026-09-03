import SwiftUI

/// Оформление приложения одним местом.
///
/// Иерархия в списках делается размером и насыщенностью, а не цветом:
/// цветовая иерархия рассыпается в тёмной теме и не читается при цветовой
/// слепоте. Цвет здесь отвечает только за опознание действия.
public enum Theme {
    /// Приглушённая зелень: имя приложения — лист, и акцент отсылает к нему,
    /// не превращая документы в яркую витрину.
    public static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.44, green: 0.75, blue: 0.60, alpha: 1)
            : UIColor(red: 0.18, green: 0.42, blue: 0.33, alpha: 1)
    })

    /// Подложка страницы. В тёмной теме лист не белый: белый прямоугольник
    /// ночью бьёт по глазам сильнее, чем помогает.
    public static let paper = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.14, alpha: 1)
            : UIColor.white
    })

    public static let pageCorner: CGFloat = 8
    public static let cardCorner: CGFloat = 14

    /// Предельное число строк в названии. Задано явно: без предела строка
    /// списка при крупном системном шрифте занимает треть экрана.
    public static let titleLineLimit = 2
    public static let subtitleLineLimit = 1
}

extension View {
    /// Название в списке: одно главное на строку, ужимается достойно.
    func documentTitleStyle() -> some View {
        font(.headline)
            .lineLimit(Theme.titleLineLimit)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
    }

    func documentSubtitleStyle() -> some View {
        font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(Theme.subtitleLineLimit)
            .truncationMode(.tail)
    }
}
