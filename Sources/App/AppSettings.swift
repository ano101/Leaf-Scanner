import Foundation
import SwiftUI

/// Оформление, выбранное человеком.
///
/// «Системная» стоит первой и по умолчанию: телефон уже знает, светло
/// сейчас или темно, и спорить с ним приложению незачем. Явный выбор нужен
/// тем, у кого система переключается по расписанию, а документы читать
/// удобнее всегда одинаково.
public enum AppTheme: String, Sendable, CaseIterable, Codable {
    case system
    case light
    case dark

    public var titleKey: String { "settings.theme.\(rawValue)" }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor
@Observable
public final class AppSettings {
    private enum Key {
        static let theme = "settings.theme"
        static let expiryReminders = "settings.expiryReminders"
    }

    private let defaults: UserDefaults

    public var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: Key.theme) }
    }

    public var expiryRemindersEnabled: Bool {
        didSet { defaults.set(expiryRemindersEnabled, forKey: Key.expiryReminders) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.theme = defaults.string(forKey: Key.theme)
            .flatMap(AppTheme.init(rawValue:)) ?? .system
        self.expiryRemindersEnabled = defaults.bool(forKey: Key.expiryReminders)
    }
}
