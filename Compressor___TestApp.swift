import SwiftUI

@main
struct CompressrApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // This sets the window title
                    if let window = NSApplication.shared.windows.first {
                        window.title = "Compressr"
                    }
                }
        }
    }
}
