import Foundation

/// Поиск даты окончания действия в распознанном тексте.
///
/// Сканер, который знает, что паспорт истекает через месяц, перестаёт быть
/// папкой с файлами и становится архивом, который сторожит. Отдельные
/// приложения для этого существуют, но они не сканеры: человек ведёт архив
/// в одном месте, а сроки в другом.
///
/// Дата принимается только рядом с ключевым словом. Без этого дата договора
/// или дата рождения превратилась бы в срок, и приложение начало бы
/// напоминать о том, чего нет, — а подсказка, которой не верят, хуже
/// её отсутствия.
public struct ExpiryDetector: Sendable {
    /// Насколько далеко от ключевого слова ищется дата. Больше — начинают
    /// попадаться даты из соседних строк.
    private static let searchWindow = 60

    private static let keywords = [
        "действителен до", "действительна до", "действительно до",
        "срок действия", "годен до", "годна до", "действует до",
        "valid until", "valid till", "date of expiry", "expiry date",
        "expires on", "expires",
    ]

    public init() {}

    public func detect(in text: String?) -> Date? {
        guard let text, text.isEmpty == false else { return nil }

        let lowered = text.lowercased()

        for keyword in Self.keywords {
            var searchStart = lowered.startIndex

            while let range = lowered.range(of: keyword, range: searchStart..<lowered.endIndex) {
                let windowEnd = lowered.index(
                    range.upperBound,
                    offsetBy: Self.searchWindow,
                    limitedBy: lowered.endIndex
                ) ?? lowered.endIndex

                if let date = firstDate(in: String(lowered[range.upperBound..<windowEnd])) {
                    return date
                }
                searchStart = range.upperBound
            }
        }

        return nil
    }

    private func firstDate(in fragment: String) -> Date? {
        for pattern in DatePattern.all {
            guard let regex = try? Regex(pattern.expression),
                  let match = fragment.firstMatch(of: regex) else { continue }
            if let date = pattern.date(from: match) { return date }
        }
        return nil
    }
}

/// Записи дат, встречающиеся в документах. Вынесены отдельно, чтобы добавить
/// новую запись можно было, не трогая сам поиск.
/// Готовое выражение здесь не хранится нарочно: `Regex` не переносится
/// между задачами, а разбор срока идёт в фоне после распознавания.
/// Хранится строка, а выражение собирается на месте — это происходит
/// раз на документ, и цена такой сборки незаметна.
private struct DatePattern: Sendable {
    let expression: String
    let order: [Component]

    enum Component: Sendable {
        case day
        case month
        case year
    }

    static let all: [DatePattern] = [
        DatePattern(expression: #"(\d{4})-(\d{2})-(\d{2})"#, order: [.year, .month, .day]),
        DatePattern(expression: #"(\d{1,2})[.\-/](\d{1,2})[.\-/](\d{4})"#, order: [.day, .month, .year]),
        DatePattern(expression: #"(\d{1,2})[.\-/](\d{1,2})[.\-/](\d{2})\b"#, order: [.day, .month, .year]),
    ]

    func date(from match: Regex<AnyRegexOutput>.Match) -> Date? {
        var parts: [Component: Int] = [:]

        for (index, component) in order.enumerated() {
            guard let text = match.output[index + 1].substring, let value = Int(text) else {
                return nil
            }
            parts[component] = value
        }

        guard var year = parts[.year], let month = parts[.month], let day = parts[.day] else {
            return nil
        }

        // Двузначный год в документе всегда означает нынешний век:
        // «годен до 26» — это две тысячи двадцать шестой, а не тысяча
        // девятьсот двадцать шестой.
        if year < 100 { year += 2000 }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12

        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: components) else { return nil }

        // Календарь охотно принимает тридцать второе число, переводя его
        // на следующий месяц. Такая дата — след ошибки распознавания,
        // а не срок, и принимать её нельзя.
        let restored = calendar.dateComponents([.year, .month, .day], from: date)
        guard restored.year == year, restored.month == month, restored.day == day else {
            return nil
        }

        return date
    }
}
