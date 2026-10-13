import SwiftUI

@main
struct DotEnvApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 640, idealWidth: 860, maxWidth: .infinity,
                       minHeight: 720, idealHeight: 960, maxHeight: .infinity)
                .navigationTitle(".env One Click Miner")
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

    }
}
