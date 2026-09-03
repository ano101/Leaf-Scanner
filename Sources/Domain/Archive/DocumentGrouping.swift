import Foundation

public struct DocumentGroup: Identifiable, Equatable, Sendable {
    public let id: String
    public let titleKey: String
    public let documents: [Document]
}

/// Разбиение архива на группы с заголовками.
///
/// Плоский список одинаковых по весу карточек перестаёт читаться уже
/// с седьмой строки: глазу не за что зацепиться. Заголовки дают опору
/// при прокрутке и отвечают на вопрос «где то, что я снимал вчера».
public enum DocumentGrouping {
    private enum Span {
        static let week = 7.0 * 86_400
    }

    public static func group(_ documents: [Document], now: Date) -> [DocumentGroup] {
        let calendar = Calendar.current

        var today: [Document] = []
        var week: [Document] = []
        var earlier: [Document] = []

        for document in documents {
            if calendar.isDate(document.updatedAt, inSameDayAs: now) {
                today.append(document)
            } else if now.timeIntervalSince(document.updatedAt) < Span.week {
                week.append(document)
            } else {
                earlier.append(document)
            }
        }

        // Пустая группа не показывается: заголовок без содержимого — это шум,
        // который занимает строку и ничего не сообщает.
        return [
            ("today", "archive.group.today", today),
            ("week", "archive.group.week", week),
            ("earlier", "archive.group.earlier", earlier),
        ]
        .compactMap { id, titleKey, documents in
            guard documents.isEmpty == false else { return nil }
            return DocumentGroup(
                id: id,
                titleKey: titleKey,
                documents: documents.sorted { $0.updatedAt > $1.updatedAt }
            )
        }
    }
}
