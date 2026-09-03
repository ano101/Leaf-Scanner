import Testing
@testable import Leaf

@Suite("Поиск персональных данных")
struct SensitiveDataDetectorTests {
    private let detector = SensitiveDataDetector()

    private func line(_ text: String) -> RecognizedLine {
        RecognizedLine(text: text, box: NormalizedRect(x: 0.1, y: 0.2, width: 0.6, height: 0.05))
    }

    private func kinds(_ text: String) -> [SensitiveKind] {
        detector.detect(in: [line(text)]).map(\.kind)
    }

    @Test("номер карты с пробелами опознаётся")
    func cardNumberWithSpacesIsDetected() {
        #expect(kinds("4276 1300 0000 1119").contains(.cardNumber))
    }

    @Test("номер карты слитно опознаётся")
    func cardNumberWithoutSpacesIsDetected() {
        #expect(kinds("Оплата картой 4276130000001119").contains(.cardNumber))
    }

    @Test("шестнадцать цифр без контрольной суммы картой не считаются")
    func sixteenDigitsFailingChecksumAreNotACard() {
        // Иначе любой длинный номер договора закрывался бы как карта,
        // и человек перестал бы доверять подсказке.
        #expect(kinds("1234567890123456").contains(.cardNumber) == false)
    }

    @Test("ИНН с верной контрольной суммой опознаётся")
    func taxIdWithValidChecksumIsDetected() {
        #expect(kinds("ИНН 7707083893").contains(.taxID))
    }

    @Test("ИНН с испорченной цифрой не опознаётся")
    func taxIdWithBrokenDigitIsNotDetected() {
        #expect(kinds("ИНН 7707083894").contains(.taxID) == false)
    }

    @Test("длинный ИНН из двенадцати цифр опознаётся")
    func twelveDigitTaxIdIsDetected() {
        #expect(kinds("ИНН 500100732259").contains(.taxID))
    }

    @Test("серия и номер паспорта опознаются")
    func passportSeriesAndNumberAreDetected() {
        #expect(kinds("45 12 345678").contains(.passport))
        #expect(kinds("4512 345678").contains(.passport))
    }

    @Test("телефон опознаётся в привычных записях")
    func phoneIsDetectedInCommonForms() {
        #expect(kinds("+7 999 123-45-67").contains(.phone))
        #expect(kinds("8 (999) 123 45 67").contains(.phone))
    }

    @Test("даты и суммы не дают ложных срабатываний")
    func datesAndAmountsDoNotFalselyTrigger() {
        #expect(kinds("Договор от 12.03.2026 на сумму 150 000 рублей").isEmpty)
        #expect(kinds("Страница 3 из 12").isEmpty)
        #expect(kinds("Приложение № 2").isEmpty)
    }

    @Test("находка указывает на рамку своей строки")
    func matchPointsAtItsOwnLineBox() {
        let matches = detector.detect(in: [line("4276 1300 0000 1119")])

        #expect(matches.count == 1)
        #expect(matches.first?.box == NormalizedRect(x: 0.1, y: 0.2, width: 0.6, height: 0.05))
    }

    @Test("в одной строке находятся несколько разных данных")
    func severalKindsAreFoundInOneLine() {
        let found = Set(kinds("ИНН 7707083893, тел. +7 999 123-45-67"))

        #expect(found.contains(.taxID))
        #expect(found.contains(.phone))
    }

    @Test("пустой список строк не даёт находок и не бросает")
    func emptyInputGivesNoMatches() {
        #expect(detector.detect(in: []).isEmpty)
    }
}
