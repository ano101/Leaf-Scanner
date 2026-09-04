import Foundation
import Testing
@testable import Leaf

@Suite("Срок действия документа")
struct ExpiryDetectorTests {
    private let detector = ExpiryDetector()

    private func date(_ day: Int, _ month: Int, _ year: Int) -> Date {
        var components = DateComponents()
        components.day = day
        components.month = month
        components.year = year
        components.hour = 12
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private func found(_ text: String) -> Date? {
        detector.detect(in: text)
    }

    private func sameDay(_ first: Date?, _ second: Date) -> Bool {
        guard let first else { return false }
        return Calendar(identifier: .gregorian).isDate(first, inSameDayAs: second)
    }

    @Test("«действителен до» с датой через точку")
    func validUntilWithDots() {
        #expect(sameDay(found("ПАСПОРТ\nДействителен до 03.03.2030"), date(3, 3, 2030)))
    }

    @Test("«срок действия» с датой через косую черту")
    func validityWithSlashes() {
        #expect(sameDay(found("Срок действия: 15/07/2027"), date(15, 7, 2027)))
    }

    @Test("английское «valid until» с датой по годам")
    func englishValidUntil() {
        #expect(sameDay(found("Valid until 2029-01-31"), date(31, 1, 2029)))
    }

    @Test("двузначный год читается как двадцать первый век")
    func twoDigitYearIsReadAsThisCentury() {
        #expect(sameDay(found("Годен до 01.12.26"), date(1, 12, 2026)))
    }

    @Test("дата без ключевых слов сроком не считается")
    func dateWithoutKeywordsIsNotAnExpiry() {
        // Иначе дата договора или дата рождения превратилась бы в срок,
        // и приложение начало бы напоминать о том, чего нет.
        #expect(found("Договор от 12.03.2026 на сумму 150 000 рублей") == nil)
        #expect(found("Дата рождения 04.04.1985") == nil)
    }

    @Test("берётся дата после ключевого слова, а не первая в тексте")
    func theDateAfterTheKeywordWinsNotTheFirstOne() {
        let text = "Выдан 04.04.2020\nДействителен до 04.04.2030"
        #expect(sameDay(found(text), date(4, 4, 2030)))
    }

    @Test("уже истёкший срок тоже распознаётся")
    func alreadyExpiredIsStillDetected() {
        // Просроченный документ — самый важный случай: человек обязан
        // узнать об этом от приложения, а не от окошка в учреждении.
        #expect(sameDay(found("Действителен до 01.01.2020"), date(1, 1, 2020)))
    }

    @Test("невозможная дата не принимается")
    func impossibleDateIsRejected() {
        #expect(found("Действителен до 32.13.2030") == nil)
    }

    @Test("пустой текст не даёт срока и не роняет разбор")
    func emptyTextGivesNothing() {
        #expect(found("") == nil)
        #expect(detector.detect(in: nil) == nil)
    }

    @Test("ключевое слово без даты рядом ничего не даёт")
    func keywordWithoutANearbyDateGivesNothing() {
        #expect(found("Действителен до окончания срока полномочий") == nil)
    }
}

@Suite("Напоминания о сроке")
struct ExpiryReminderTests {
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    private func inDays(_ days: Int) -> Date {
        now.addingTimeInterval(Double(days) * 86_400)
    }

    @Test("для далёкого срока назначаются все три напоминания")
    func distantExpiryGetsEveryReminder() {
        let dates = ExpiryReminder.dates(for: inDays(200), now: now)
        #expect(dates.count == ExpiryReminder.daysBefore.count)
    }

    @Test("прошедшие напоминания не назначаются")
    func remindersInThePastAreNotScheduled() {
        // До срока двадцать дней: напоминать за девяносто и за тридцать
        // уже поздно, за семь — ещё нет.
        let dates = ExpiryReminder.dates(for: inDays(20), now: now)
        #expect(dates.count == 1)
        #expect(dates.allSatisfy { $0 > now })
    }

    @Test("истёкшему документу напоминания не назначаются")
    func expiredDocumentGetsNoReminders() {
        #expect(ExpiryReminder.dates(for: inDays(-5), now: now).isEmpty)
    }

    @Test("напоминания идут от раннего к позднему")
    func remindersGoFromEarliestToLatest() {
        let dates = ExpiryReminder.dates(for: inDays(200), now: now)
        #expect(dates == dates.sorted())
    }

    @Test("документ считается истекающим скоро за месяц до срока")
    func documentCountsAsExpiringSoonAMonthBefore() {
        #expect(ExpiryReminder.isExpiringSoon(inDays(20), now: now))
        #expect(ExpiryReminder.isExpiringSoon(inDays(200), now: now) == false)
        #expect(ExpiryReminder.isExpired(inDays(-1), now: now))
    }
}
