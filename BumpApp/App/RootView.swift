import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            switch appState.authState {
            case .signedOut:
                SignUpView()
            case .onboarding:
                OnboardingView()
            case .signedIn:
                MainTabView()
            }
        }
        .background(BumpColors.background.ignoresSafeArea())
    }
}
