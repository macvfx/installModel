import SwiftUI

@main
struct InstallModelApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 760, minHeight: 720)
        }
        .windowResizability(.contentMinSize)
    }
}
