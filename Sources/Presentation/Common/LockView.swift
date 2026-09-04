import SwiftUI

/// Запертый экран. Показывается именно замок, а не пустой список: пустота
/// на месте архива читается как потеря документов.
struct LockView: View {
    let lock: AppLock

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.accent)

            Text("lock.title")
                .font(.title3.weight(.semibold))

            if case let .refused(messageKey) = lock.state {
                Text(LocalizedStringKey(messageKey))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                Task { await lock.unlock() }
            } label: {
                Text("lock.unlock")
            }
            .buttonStyle(.prominentAccentCompact)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
