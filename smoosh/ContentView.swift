import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

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

            BottomButtonsView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
