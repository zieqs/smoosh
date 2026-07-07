import SwiftUI

@main
struct smooshApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra ("Smoosh", systemImage: "rectangle.compress.vertical") {
            ContentView()
                .environment(appState)
                .frame(width: 300)
        }
        .menuBarExtraStyle(.window)
    }
}
