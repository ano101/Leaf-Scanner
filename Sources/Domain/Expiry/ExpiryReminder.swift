import Foundation

/// Когда напоминать о сроке.
///
/// Три захода: за три месяца — чтобы успеть записаться, за месяц — чтобы
/// собрать документы, за неделю — последний срок. Одно напоминание человек
/// пропустит, десяток — отключит.
public enum ExpiryReminder {
    public static let daysBefore = [90, 30, 7]
    public static let soonInDays = 30

    public static func dates(for expiry: Date, now: Date = Date()) -> [Date] {
        daysBefore
            .map { expiry.addingTimeInterval(-Double($0) * 86_400) }
            .filter { $0 > now }
            .sorted()
    }

    public static func isExpired(_ expiry: Date, now: Date = Date()) -> Bool {
        expiry < now
    }

    public static func isExpiringSoon(_ expiry: Date, now: Date = Date()) -> Bool {
        expiry >= now && expiry <= now.addingTimeInterval(Double(soonInDays) * 86_400)
    }
}
