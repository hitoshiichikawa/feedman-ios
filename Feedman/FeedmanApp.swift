import SwiftUI

@main
struct FeedmanApp: App {
    @StateObject private var environment = AppEnvironment.production()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .task {
                    await environment.restoreSessionAtLaunch()
                }
        }
    }
}
