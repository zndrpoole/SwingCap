import SwiftUI

@main
struct SwingCapApp: App {
    var body: some Scene {
        WindowGroup {
            SessionView()
                .preferredColorScheme(.dark)
        }
    }
}
