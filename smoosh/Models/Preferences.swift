import Foundation

@Observable
final class Preferences {
    static let shared = Preferences()

    var useAggressivePDFCompression: Bool {
        didSet {
            UserDefaults.standard.set(useAggressivePDFCompression, forKey: "useAggressivePDFCompression")
        }
    }

    private init() {
        useAggressivePDFCompression = UserDefaults.standard.bool(forKey: "useAggressivePDFCompression")
    }
}
