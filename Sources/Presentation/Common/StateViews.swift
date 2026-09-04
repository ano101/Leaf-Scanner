import SwiftUI

/// Экран без содержимого — это не надпись, а предложение действия.
/// «Ничего не найдено» без кнопки оставляет человека в тупике.
struct EmptyStateView: View {
    let iconName: String
    let titleKey: LocalizedStringKey
    let messageKey: LocalizedStringKey
    let actionKey: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(Theme.accent)

            Text(titleKey)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(messageKey)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button(action: action) {
                Text(actionKey)
            }
            .buttonStyle(.prominentAccentCompact)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Отказ тоже даёт действие: сообщение без «повторить» вынуждает
/// перезапускать приложение.
struct FailureView: View {
    let messageKey: LocalizedStringKey
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)

            Text(messageKey)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button(action: retry) {
                Text("common.retry")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Читаемый вес файла. Человек оперирует мегабайтами, а не числом байт.
enum ByteText {
    static func string(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB]
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
