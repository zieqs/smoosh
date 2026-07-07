import SwiftUI

@main
struct smooshApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environment(appState)
                .frame(width: 300)
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
        }
    }
}
