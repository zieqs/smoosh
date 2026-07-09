import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()

        if let folderPath = ProcessInfo.processInfo.stressTestFolderPath {
            let folderURL: URL
            if folderPath.hasPrefix("file://") {
                folderURL = URL(fileURLWithPath: (URL(string: folderPath)?.path) ?? folderPath)
            } else {
                folderURL = URL(fileURLWithPath: folderPath)
            }
            statusBarController?.runStressTest(folderURL: folderURL)
        }
    }
}
