import SwiftUI

@main
struct FeedmanApp: App {
    @StateObject private var environment = AppEnvironment.preview

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
        }
    }
}

