import SwiftUI

@Observable
final class AppState {
    var history: [OptimizationItem] = []

    func addItem(_ item: OptimizationItem) {
        history.insert(item, at: 0)
        notifyBubbleUpdate()
    }

    func replaceItem(_ id: UUID, with item: OptimizationItem) {
        if let index = history.firstIndex(where: { $0.id == id }) {
            history[index] = item
            notifyBubbleUpdate()
        }
    }

    func dismissItem(_ id: UUID) {
        if let index = history.firstIndex(where: { $0.id == id }) {
            history[index].isBubbleVisible = false
            notifyBubbleUpdate()
        }
    }

    func removeItems(at offsets: IndexSet) {
        history.remove(atOffsets: offsets)
        notifyBubbleUpdate()
    }

    func clearHistory() {
        history.removeAll()
        notifyBubbleUpdate()
    }

    var visibleBubbles: [OptimizationItem] {
        history.filter { $0.isBubbleVisible }
    }

    private func notifyBubbleUpdate() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .appStateBubbleUpdate, object: nil)
        }
    }
}

extension Notification.Name {
    static let appStateBubbleUpdate = Notification.Name("com.zieqs.smoosh.appStateBubbleUpdate")
}
