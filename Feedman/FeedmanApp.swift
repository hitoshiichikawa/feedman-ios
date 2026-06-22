import SwiftUI

@main
struct FeedmanApp: App {
    @UIApplicationDelegateAdaptor(FeedmanAppDelegate.self) private var appDelegate
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
