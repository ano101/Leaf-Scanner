import SwiftUI

@main
struct LeafApp: App {
    @State private var services: AppServices?
    @State private var startupError: String?
    @State private var isStarting = true
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                if let services {
                    RootView(services: services)
                } else if startupError != nil {
                    FailureView(messageKey: "app.error.start") { start() }
                }

                if isStarting {
                    SplashView()
                        .transition(.opacity)
                        .task { await openArchive() }
                }
            }
            .tint(Theme.accent)
            .preferredColorScheme(services?.settings.theme.colorScheme)
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

    /// Заставка держится ровно столько, сколько нужно, чтобы человек успел
    /// её увидеть, и ни секундой дольше. Открытие архива идёт параллельно,
    /// а не после неё.
    private func openArchive() async {
        start()
        try? await Task.sleep(for: .milliseconds(650))
        withAnimation(.easeOut(duration: 0.25)) { isStarting = false }
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
