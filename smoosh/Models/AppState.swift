import SwiftUI

@Observable
final class AppState {
    var history: [OptimizationItem] = []
    var onDidChange: (() -> Void)?

    func addItem(_ item: OptimizationItem) {
        history.insert(item, at: 0)
        onDidChange?()
    }

    func replaceItem(_ id: UUID, with item: OptimizationItem) {
        if let index = history.firstIndex(where: { $0.id == id }) {
            history[index] = item
            onDidChange?()
        }
    }

    func dismissItem(_ id: UUID) {
        if let index = history.firstIndex(where: { $0.id == id }) {
            history[index].isBubbleVisible = false
            onDidChange?()
        }
    }

    func removeItems(at offsets: IndexSet) {
        history.remove(atOffsets: offsets)
        onDidChange?()
    }

    func clearHistory() {
        history.removeAll()
        onDidChange?()
    }

    var visibleBubbles: [OptimizationItem] {
        history.filter { $0.isBubbleVisible }
    }
}
