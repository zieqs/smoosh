import SwiftUI

@Observable
final class AppState {
    var history: [OptimizationItem] = []

    func addItem(_ item: OptimizationItem) {
        history.insert(item, at: 0)
        postChangeNotification()
    }

    func replaceItem(_ id: UUID, with item: OptimizationItem) {
        if let index = history.firstIndex(where: { $0.id == id }) {
            history[index] = item
            postChangeNotification()
        }
    }

    func dismissItem(_ id: UUID) {
        if let index = history.firstIndex(where: { $0.id == id }) {
            history[index].isBubbleVisible = false
            postChangeNotification()
        }
    }

    func removeItems(at offsets: IndexSet) {
        history.remove(atOffsets: offsets)
        postChangeNotification()
    }

    func clearHistory() {
        history.removeAll()
        postChangeNotification()
    }

    var visibleBubbles: [OptimizationItem] {
        history.filter { $0.isBubbleVisible }
    }

    private func postChangeNotification() {
        NotificationCenter.default.post(name: .appStateDidChange, object: nil)
    }
}

extension Notification.Name {
    static let appStateDidChange = Notification.Name("com.zieqs.smoosh.appStateDidChange")
}
