import Foundation
import Testing
@testable import Leaf

@Suite("Группировка архива")
struct DocumentGroupingTests {
    private let now = Date(timeIntervalSince1970: 1_772_000_000)

    private func document(daysAgo: Double, name: String = "Документ") -> Document {
        Document(name: name, updatedAt: now.addingTimeInterval(-daysAgo * 86_400))
    }

    @Test("сегодняшние, недавние и старые документы разложены по группам")
    func todayRecentAndOlderAreSeparated() {
        let groups = DocumentGrouping.group(
            [document(daysAgo: 0.1), document(daysAgo: 3), document(daysAgo: 40)],
            now: now
        )

        #expect(groups.count == 3)
        #expect(groups.map(\.titleKey) == [
            "archive.group.today",
            "archive.group.week",
            "archive.group.earlier",
        ])
    }

    @Test("пустые группы не показываются — заголовок без содержимого это мусор")
    func emptyGroupsAreNotShown() {
        let groups = DocumentGrouping.group([document(daysAgo: 0.2)], now: now)

        #expect(groups.count == 1)
        #expect(groups.first?.titleKey == "archive.group.today")
    }

    @Test("внутри группы новые документы идут первыми")
    func newestComesFirstInsideGroup() {
        let older = document(daysAgo: 5, name: "Старый")
        let newer = document(daysAgo: 2, name: "Новый")

        let groups = DocumentGrouping.group([older, newer], now: now)
        let week = try? #require(groups.first)

        #expect(week?.documents.count == 2)
        #expect(week?.documents.first?.name == "Новый")
    }

    @Test("пустой архив не даёт ни одной группы")
    func emptyArchiveGivesNoGroups() {
        #expect(DocumentGrouping.group([], now: now).isEmpty)
    }

    @Test("группа опознаётся по устойчивому ключу, а не по заголовку")
    func groupIsIdentifiedByStableKey() {
        let groups = DocumentGrouping.group([document(daysAgo: 0.1)], now: now)

        #expect(groups.first?.id == "today")
    }
}
