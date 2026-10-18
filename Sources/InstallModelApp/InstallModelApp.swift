import SwiftUI

@main
struct InstallModelApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 760, minHeight: 720)
        }
        .windowResizability(.contentMinSize)
        .commands {
            InstallModelCommands()
        }

        Window("InstallModel Help", id: "help") {
            HelpView()
                .frame(minWidth: 660, minHeight: 620)
        }
        .windowResizability(.contentMinSize)

        Window("About InstallModel", id: "about") {
            AboutView()
                .frame(width: 480, height: 430)
        }
        .windowResizability(.contentSize)
    }
}
