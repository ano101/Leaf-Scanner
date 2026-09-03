import SwiftUI

@main
struct LeafApp: App {
    @State private var services: AppServices?
    @State private var startupError: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if let services {
                    RootView(services: services)
                } else if startupError != nil {
                    FailureView(messageKey: "app.error.start") { start() }
                } else {
                    ProgressView().task { start() }
                }
            }
            .tint(Theme.accent)
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { services?.lock.lockOnBackground() }
            }
        }
    }

    private func start() {
        do {
            services = try AppServices(root: AppServices.defaultRoot())
            startupError = nil
        } catch {
            startupError = error.localizedDescription
        }
    }
}

/// Корень приложения: замок стоит перед архивом, а не поверх него —
/// заблокированный экран не должен показывать даже названия документов.
struct RootView: View {
    let services: AppServices

    var body: some View {
        Group {
            if services.lock.isOpen {
                NavigationStack {
                    ArchiveView(services: services)
                }
            } else {
                LockView(lock: services.lock)
            }
        }
        .task { await services.lock.unlock() }
    }
}
