import SwiftUI

/// App entry point. Owns the single `SessionStore` instance and uses a
/// UserDefaults flag to decide which root view to show.
///
/// **Onboarding gate**: `hasCompletedOnboarding` is written by `OnboardingView`
/// once the user grants camera permission. Changing it from `false` → `true`
/// causes this body to re-evaluate and replace `OnboardingView` with
/// `SessionView` — no navigation stack needed.
///
/// **Environment injection**: `SessionStore` is created here (once, for the
/// entire app lifetime) and pushed down via `.environment(sessionStore)`.
/// All child views that need it declare `@Environment(SessionStore.self)`.
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
