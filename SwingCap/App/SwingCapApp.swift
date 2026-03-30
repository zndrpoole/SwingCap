import SwiftUI

@main
struct SwingCapApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var sessionStore = SessionStore()

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                SessionView()
                    .environment(sessionStore)
                    .preferredColorScheme(.dark)
            } else {
                OnboardingView()
                    .preferredColorScheme(.dark)
            }
        }
    }
}
