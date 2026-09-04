import Foundation
import UserNotifications

/// Напоминания о сроке действия документов.
///
/// Разрешение спрашивается только когда человек включает напоминания,
/// а не при первом запуске: приложение, начинающее со списка разрешений,
/// получает отказ на всё сразу.
public actor ExpiryScheduler {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    public func schedule(for document: Document) async {
        await cancel(for: document.id)

        guard let expiry = document.expiresAt else { return }

        for date in ExpiryReminder.dates(for: expiry) {
            let content = UNMutableNotificationContent()
            content.title = document.name
            content.body = String(
                format: String(localized: "expiry.notification %lld"),
                daysBetween(date, and: expiry)
            )
            content.sound = .default

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: date
            )
            let request = UNNotificationRequest(
                identifier: identifier(for: document.id, at: date),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    /// Снимаются именно напоминания этого документа: чужие сроки не должны
    /// пропадать оттого, что один документ переименовали.
    public func cancel(for id: DocumentID) async {
        let prefix = id.raw.uuidString
        let pending = await center.pendingNotificationRequests()
        let mine = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: mine)
    }

    public func cancelAll() async {
        center.removeAllPendingNotificationRequests()
    }

    private func identifier(for id: DocumentID, at date: Date) -> String {
        "\(id.raw.uuidString)|\(Int(date.timeIntervalSince1970))"
    }

    private func daysBetween(_ date: Date, and expiry: Date) -> Int {
        max(Calendar.current.dateComponents([.day], from: date, to: expiry).day ?? 0, 0)
    }
}
