import SwiftUI

@Observable
final class AppState {
    var history: [OptimizationItem] = []

    func addItem(_ item: OptimizationItem) {
        history.insert(item, at: 0)
    }

    func replaceItem(_ id: UUID, with item: OptimizationItem) {
        if let index = history.firstIndex(where: { $0.id == id }) {
            history[index] = item
        }
    }

    func dismissItem(_ id: UUID) {
        if let index = history.firstIndex(where: { $0.id == id }) {
            history[index].isBubbleVisible = false
        }
    }

    func removeItems(at offsets: IndexSet) {
        history.remove(atOffsets: offsets)
    }

    func clearHistory() {
        history.removeAll()
    }

    var visibleBubbles: [OptimizationItem] {
        history.filter { $0.isBubbleVisible }
    }
}
