import SwiftUI

/// Название документа без переноса по слогам.
///
/// SwiftUI разрывает длинное слово дефисом, когда оно шире строки:
/// «Страни-ца 3». Запрет через стиль абзаца он не соблюдает — проверено
/// на устройстве при максимальном системном шрифте.
///
/// Поэтому запрет обеспечивается иначе: чем крупнее шрифт, тем меньше строк
/// отводится названию, вплоть до одной. В одну строку переносить нечего,
/// и слово обрезается многоточием — как и требуют правила вёрстки: длинное
/// название это одна строка с обрезкой, максимум две.
struct PlainTitle: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .lineLimit(typeSize.isAccessibilitySize ? 1 : Theme.titleLineLimit)
            .minimumScaleFactor(Theme.minimumScale)
            .allowsTightening(true)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
    }
}
