import SwiftUI

@main
struct DotEnvApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 580, idealWidth: 860, maxWidth: .infinity,
                       minHeight: 480, idealHeight: 780, maxHeight: .infinity)
                .navigationTitle(".env One Click Miner")
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

    }
}
