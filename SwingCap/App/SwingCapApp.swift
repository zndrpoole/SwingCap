import SwiftUI

@main
struct SwingCapApp: App {
    @State private var sessionStore = SessionStore()

    var body: some Scene {
        WindowGroup {
            SessionView()
                .environment(sessionStore)
                .preferredColorScheme(.dark)
        }
    }
}
