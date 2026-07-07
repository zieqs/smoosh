import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 0) {
            DropZoneView()

            Divider()
                .padding(.horizontal)

            HistoryListView()

            Divider()
                .padding(.horizontal)

            TipJarButton()
        }
    }
}
