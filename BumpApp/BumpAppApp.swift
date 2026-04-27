import SwiftUI

@main
struct BumpAppMain: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
                .task {
                    appState.bootstrap()
                }
        }
    }
}
