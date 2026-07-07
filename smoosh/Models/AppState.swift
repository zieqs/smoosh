import Foundation

@Observable
final class AppState {
    var history: [OptimizationItem] = []

    func addItem(_ item: OptimizationItem) {
        history.insert(item, at: 0)
    }

    func removeItems(at offsets: IndexSet) {
        history.remove(atOffsets: offsets)
    }

    func clearHistory() {
        history.removeAll()
    }
}
