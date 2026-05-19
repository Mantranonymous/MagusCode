import SwiftUI
import os

private let logger = Logger(subsystem: "com.magus.app", category: "app")

@main
struct MagusApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentMinSize)
    }

    init() {
        logger.info("Magus démarré")
    }
}
