import SwiftUI

@main
struct SpogApp: App {
    init() {
        Analytics.configure()
        Analytics.track(.appLaunched)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
