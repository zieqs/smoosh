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
            Image(systemName: "rectangle.compress.vertical")
        }
    }
}
