import SwiftUI

@main
struct LeafApp: App {
    var body: some Scene {
        WindowGroup {
            Text(verbatim: AppInfo.name)
        }
    }
}
