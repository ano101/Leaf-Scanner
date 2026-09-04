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

    /// Надпись поверх акцента. В тёмной теме акцент светлеет, и белый текст
    /// на нём теряется — поэтому цвет надписи меняется вместе с фоном,
    /// а не задан раз и навсегда.
    public static let onAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.07, alpha: 1)
            : UIColor.white
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
    /// Насколько кегль вправе уменьшиться, лишь бы слово не разорвалось.
    public static let minimumScale = 0.7
    public static let subtitleLineLimit = 1
}

extension View {
    /// Название в списке: одно главное на строку, ужимается достойно.
    ///
    /// При крупном системном шрифте SwiftUI разрывает слово дефисом —
    /// «Страни-ца». Это запрещено: разорванное слово читается хуже
    /// обрезанного. Уменьшение кегля и подтяжка межбуквенных просветов
    /// дают слову уместиться целиком, а если и это не помогает —
    /// строка обрезается многоточием.
    func documentTitleStyle() -> some View {
        font(.headline)
            .lineLimit(Theme.titleLineLimit)
            .minimumScaleFactor(Theme.minimumScale)
            .allowsTightening(true)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
    }

    func documentSubtitleStyle() -> some View {
        font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(Theme.subtitleLineLimit)
            .minimumScaleFactor(Theme.minimumScale)
            .allowsTightening(true)
            .truncationMode(.tail)
    }
}


/// Главное действие экрана. Отдельный стиль нужен, чтобы контраст надписи
/// не приходилось помнить в каждом месте, где такая кнопка появляется.
struct ProminentAccentButtonStyle: ButtonStyle {
    var fillsWidth = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            // Надпись кнопки не переносится и не растёт бесконечно: при
            // максимальном системном шрифте она иначе раздувает кнопку
            // в круг, накрывающий список под ней.
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .allowsTightening(true)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .foregroundStyle(Theme.onAccent)
            .padding(.vertical, 12)
            .padding(.horizontal, fillsWidth ? 16 : 22)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .background(Theme.accent, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

extension ButtonStyle where Self == ProminentAccentButtonStyle {
    static var prominentAccent: ProminentAccentButtonStyle { ProminentAccentButtonStyle() }
    static var prominentAccentCompact: ProminentAccentButtonStyle {
        ProminentAccentButtonStyle(fillsWidth: false)
    }
}

/// Второе по важности действие рядом с главным: та же форма и те же поля,
/// но тише по цвету. Одинаковые поля важны — при разных кнопка рядом
/// выглядит перекошенной.
struct SecondaryAccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .allowsTightening(true)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .foregroundStyle(Theme.accent)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Theme.accent.opacity(0.14), in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == SecondaryAccentButtonStyle {
    static var secondaryAccent: SecondaryAccentButtonStyle { SecondaryAccentButtonStyle() }
}
