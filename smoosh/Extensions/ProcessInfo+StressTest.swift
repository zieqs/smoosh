import Foundation

extension ProcessInfo {
    /// Returns the folder path passed via `--smoosh-stress-test <folder>` if present.
    var stressTestFolderPath: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--smoosh-stress-test"),
              index + 1 < args.count else {
            return nil
        }
        return args[index + 1]
    }
}
