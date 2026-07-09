import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(Preferences.self) private var preferences
    @State private var showPreferences = false

    var body: some View {
        VStack(spacing: 0) {
            if appState.history.isEmpty {
                Spacer()
                DropZoneView()
                Spacer()
            } else {
                DropZoneView()
                HistoryListView()
            }

            Divider()
                .padding(.horizontal)

            BottomButtonsView(showPreferences: $showPreferences)
        }
        .frame(width: 300)
        .frame(minHeight: 280)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
        .sheet(isPresented: $showPreferences) {
            PreferencesView()
        }
    }
}
