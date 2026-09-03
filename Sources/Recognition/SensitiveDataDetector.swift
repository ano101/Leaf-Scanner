import Foundation

public enum SensitiveKind: String, Sendable, Codable, CaseIterable {
    case cardNumber
    case passport
    case taxID
    case phone

    public var titleKey: String { "sensitive.\(rawValue)" }
}

public struct SensitiveMatch: Equatable, Sendable, Identifiable {
    public let id: Identifier<SensitiveMatch>
    public let kind: SensitiveKind
    public let box: NormalizedRect
    public let text: String

    public init(
        id: Identifier<SensitiveMatch> = .init(),
        kind: SensitiveKind,
        box: NormalizedRect,
        text: String
    ) {
        self.id = id
        self.kind = kind
        self.box = box
        self.text = text
    }
}

/// Подсказка «здесь номер карты, закрыть?».
///
/// Главное требование к ней — не врать. Подсказка, которая срабатывает
/// на номере договора и на номере страницы, обучает человека нажимать
/// «нет», и в тот раз, когда она права, он тоже нажмёт «нет». Поэтому
/// всё, что имеет контрольную сумму, проверяется по ней.
///
/// Рамка находки — это рамка всей строки: распознавание не даёт координат
/// отдельных символов, и закрывать приходится строку целиком.
public struct SensitiveDataDetector: Sendable {
    public init() {}

    public func detect(in lines: [RecognizedLine]) -> [SensitiveMatch] {
        lines.flatMap { line in
            kinds(in: line.text).map {
                SensitiveMatch(kind: $0, box: line.box, text: line.text)
            }
        }
    }

    private func kinds(in text: String) -> [SensitiveKind] {
        var found: [SensitiveKind] = []

        if containsCardNumber(text) { found.append(.cardNumber) }
        if containsPassport(text) { found.append(.passport) }
        if containsTaxID(text) { found.append(.taxID) }
        if containsPhone(text) { found.append(.phone) }

        return found
    }

    // MARK: - Карта

    private func containsCardNumber(_ text: String) -> Bool {
        digitGroups(in: text, separators: [" ", "-"]).contains { group in
            (13...19).contains(group.count) && passesLuhn(group)
        }
    }

    /// Проверка Луна: тот самый признак, по которому номер карты отличается
    /// от любого другого длинного числа.
    private func passesLuhn(_ digits: [Int]) -> Bool {
        var sum = 0
        for (index, digit) in digits.reversed().enumerated() {
            if index % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }

    // MARK: - Паспорт

    /// Серия и номер разделены пробелом — без разделителя десять цифр подряд
    /// неотличимы от ИНН, и обе подсказки были бы догадкой.
    private func containsPassport(_ text: String) -> Bool {
        let pattern = #"\b\d{2}\s?\d{2}\s+\d{6}\b"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - ИНН

    private func containsTaxID(_ text: String) -> Bool {
        digitGroups(in: text, separators: []).contains { group in
            switch group.count {
            case 10: isValidShortTaxID(group)
            case 12: isValidLongTaxID(group)
            default: false
            }
        }
    }

    private func isValidShortTaxID(_ digits: [Int]) -> Bool {
        checksum(digits, weights: [2, 4, 10, 3, 5, 9, 4, 6, 8]) == digits[9]
    }

    private func isValidLongTaxID(_ digits: [Int]) -> Bool {
        checksum(digits, weights: [7, 2, 4, 10, 3, 5, 9, 4, 6, 8]) == digits[10]
            && checksum(digits, weights: [3, 7, 2, 4, 10, 3, 5, 9, 4, 6, 8]) == digits[11]
    }

    private func checksum(_ digits: [Int], weights: [Int]) -> Int {
        let sum = zip(digits, weights).reduce(0) { $0 + $1.0 * $1.1 }
        return sum % 11 % 10
    }

    // MARK: - Телефон

    private func containsPhone(_ text: String) -> Bool {
        let pattern = #"(\+7|\b8)[\s\-\(]*\d{3}[\s\-\)]*\d{3}[\s\-]*\d{2}[\s\-]*\d{2}\b"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Разбор чисел

    /// Непрерывные группы цифр. Разделители внутри группы разрешены только
    /// перечисленные: иначе «сумма 150 000» склеилась бы в одно число.
    private func digitGroups(in text: String, separators: Set<Character>) -> [[Int]] {
        var groups: [[Int]] = []
        var current: [Int] = []
        var pendingSeparators = 0

        for character in text {
            if let digit = character.wholeNumberValue, character.isNumber {
                current.append(digit)
                pendingSeparators = 0
            } else if separators.contains(character), current.isEmpty == false, pendingSeparators == 0 {
                pendingSeparators = 1
            } else {
                if current.isEmpty == false { groups.append(current) }
                current = []
                pendingSeparators = 0
            }
        }

        if current.isEmpty == false { groups.append(current) }
        return groups
    }
}
