import SwiftUI

struct SettingsView: View {
    let settings: AppSettings
    let lock: AppLock
    let expiry: ExpiryScheduler

    @Environment(\.dismiss) private var dismiss
    @State private var lockEnabled: Bool
    @State private var remindersEnabled: Bool

    init(settings: AppSettings, lock: AppLock, expiry: ExpiryScheduler) {
        self.settings = settings
        self.lock = lock
        self.expiry = expiry
        _lockEnabled = State(initialValue: lock.isEnabled)
        _remindersEnabled = State(initialValue: settings.expiryRemindersEnabled)
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
                Toggle("settings.expiry", isOn: $remindersEnabled)
                    .onChange(of: remindersEnabled) { _, enabled in
                        Task {
                            // Разрешение спрашивается в момент включения,
                            // а не при запуске: приложение, начинающее
                            // со списка разрешений, получает отказ на всё.
                            if enabled, await expiry.requestPermission() == false {
                                remindersEnabled = false
                                settings.expiryRemindersEnabled = false
                                return
                            }
                            settings.expiryRemindersEnabled = enabled
                            if enabled == false { await expiry.cancelAll() }
                        }
                    }
            } footer: {
                Text("settings.expiry.hint")
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
