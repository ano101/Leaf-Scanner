import SwiftUI

struct SettingsView: View {
    let settings: AppSettings
    let lock: AppLock

    @Environment(\.dismiss) private var dismiss
    @State private var lockEnabled: Bool

    init(settings: AppSettings, lock: AppLock) {
        self.settings = settings
        self.lock = lock
        _lockEnabled = State(initialValue: lock.isEnabled)
    }

    var body: some View {
        Form {
            Section("settings.theme") {
                Picker("settings.theme", selection: Binding(
                    get: { settings.theme },
                    set: { settings.theme = $0 }
                )) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Text(LocalizedStringKey(theme.titleKey)).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section {
                Toggle("settings.lock", isOn: $lockEnabled)
                    .onChange(of: lockEnabled) { _, enabled in
                        lock.isEnabled = enabled
                    }
            } footer: {
                Text("settings.lock.hint")
            }

            Section {
                Label("settings.privacy", systemImage: "lock.shield")
                    .foregroundStyle(Theme.accent)
            } footer: {
                Text("settings.privacy.hint")
            }
        }
        .navigationTitle("settings.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("common.done") { dismiss() }
            }
        }
    }
}
