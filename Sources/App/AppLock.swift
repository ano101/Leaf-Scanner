import Foundation
import LocalAuthentication

/// Замок на входе в архив.
///
/// Отказ проверки оставляет экран запертым, а не пустым: пустой список
/// выглядит как потеря документов, и человек начинает искать их там,
/// где их нет.
@MainActor
@Observable
public final class AppLock {
    public enum State: Equatable, Sendable {
        case disabled
        case locked
        case unlocked
        case refused(messageKey: String)
    }

    private static let settingKey = "lock.enabled"

    public private(set) var state: State
    private let defaults: UserDefaults
    private let context: () -> LAContext

    public init(
        defaults: UserDefaults = .standard,
        context: @escaping () -> LAContext = { LAContext() }
    ) {
        self.defaults = defaults
        self.context = context
        self.state = defaults.bool(forKey: Self.settingKey) ? .locked : .disabled
    }

    public var isEnabled: Bool {
        get { defaults.bool(forKey: Self.settingKey) }
        set {
            defaults.set(newValue, forKey: Self.settingKey)
            state = newValue ? .locked : .disabled
        }
    }

    public var isOpen: Bool {
        state == .disabled || state == .unlocked
    }

    public func unlock() async {
        guard isEnabled else {
            state = .disabled
            return
        }

        let context = context()
        var error: NSError?
        // Код устройства оставлен запасным путём нарочно: без него человек
        // с мокрыми руками или в маске остаётся заперт в собственном архиве.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            state = .refused(messageKey: "lock.error.unavailable")
            return
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: String(localized: "lock.reason")
            )
            state = success ? .unlocked : .refused(messageKey: "lock.error.refused")
        } catch {
            state = .refused(messageKey: "lock.error.refused")
        }
    }

    /// Возврат из фона снова запирает: телефон, отданный в руки, не должен
    /// открывать архив только потому, что приложение уже было запущено.
    public func lockOnBackground() {
        guard isEnabled else { return }
        state = .locked
    }
}
