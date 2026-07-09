import Foundation
import UniformTypeIdentifiers

final class OptimizationCoordinator {
    static let shared = OptimizationCoordinator()

    private init() {}

    func optimize(fileAt url: URL, appState: AppState) {
        guard let utType = UTType(filenameExtension: url.pathExtension) else {
            return
        }

        if utType.conforms(to: .pdf) {
            PDFOptimizationService.shared.optimize(fileAt: url, appState: appState)
        } else if utType.conforms(to: .image) {
            ImageOptimizationService.shared.optimize(fileAt: url, appState: appState)
        } else if utType.conforms(to: .movie) {
            VideoOptimizationService.shared.optimize(fileAt: url, appState: appState)
        }
    }
}
