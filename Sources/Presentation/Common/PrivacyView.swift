import SwiftUI

/// Обещание приватности, написанное прямо в приложении.
///
/// Магазин требует ссылку на страницу в интернете, но человек читает её
/// в лучшем случае один раз до установки. Здесь то же самое лежит там,
/// где он находится, — и открывается без сети, которой у приложения
/// всё равно нет.
struct PrivacyView: View {
    @Environment(\.dismiss) private var dismiss

    /// Разделы перечислены основами ключей: ключ опознаваем сам по себе,
    /// а пара LocalizedStringKey — нет, и список из них не собрать.
    private let blocks = ["storage", "absent", "access", "outgoing"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Label {
                    Text("privacy.lead")
                        .font(.title3.weight(.semibold))
                } icon: {
                    Image(systemName: "lock.shield.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                }

                ForEach(blocks, id: \.self) { block in
                    // Ключ собирается заранее и передаётся строкой: подстановка
                    // внутри литерала LocalizedStringKey превращает его
                    // в строку формата, и перевод молча не находится.
                    let title = "privacy." + block + ".title"
                    let text = "privacy." + block + ".text"

                    VStack(alignment: .leading, spacing: 6) {
                        Text(LocalizedStringKey(title))
                            .font(.headline)
                        Text(LocalizedStringKey(text))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("privacy.updated")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationTitle("privacy.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("common.done") { dismiss() }
            }
        }
    }
}
