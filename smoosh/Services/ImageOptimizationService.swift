import Foundation
import UniformTypeIdentifiers

final class ImageOptimizationService {
    static let shared = ImageOptimizationService()

    private let optimizers: [any MediaOptimizerProtocol] = [
        PNGOptimizer(),
        JPEGOptimizer(),
        GIFOptimizer()
    ]

    func optimize(fileAt url: URL, appState: AppState) {
        let item = OptimizationItem(
            id: UUID(), fileName: url.lastPathComponent,
            fileSize: (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64 ?? 0,
            optimizedSize: nil, sourceURL: url, status: .pending
        )
        let outputURL = self.outputURL(for: url)
        guard let optimizer = self.optimizer(for: url) else {
            Task { @MainActor in
                appState.addItem(item)
                appState.replaceItem(item.id, with: OptimizationItem(
                    id: item.id, fileName: url.lastPathComponent,
                    fileSize: item.fileSize, optimizedSize: nil,
                    sourceURL: url, status: .failed("Unsupported format")
                ))
            }
            return
        }

        Task { @MainActor in
            appState.addItem(item)

            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            let tempOutput = tempDir.appendingPathComponent(outputURL.lastPathComponent)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            for await state in optimizer.optimize(fileAt: url, outputURL: tempOutput) {
                switch state {
                case .processing(let progress):
                    appState.replaceItem(item.id, with: OptimizationItem(
                        id: item.id, fileName: url.lastPathComponent,
                        fileSize: item.fileSize, optimizedSize: nil,
                        sourceURL: url, status: .processing(progress)
                    ))
                case .completed(let metrics):
                    if metrics.optimizedSize < item.fileSize {
                        try? FileManager.default.moveItem(at: tempOutput, to: outputURL)
                    } else {
                        try? FileManager.default.removeItem(at: tempOutput)
                    }
                    appState.replaceItem(item.id, with: OptimizationItem(
                        id: item.id, fileName: url.lastPathComponent,
                        fileSize: item.fileSize,
                        optimizedSize: metrics.optimizedSize,
                        sourceURL: url, status: .completed
                    ))
                case .failed(let error):
                    try? FileManager.default.removeItem(at: tempOutput)
                    appState.replaceItem(item.id, with: OptimizationItem(
                        id: item.id, fileName: url.lastPathComponent,
                        fileSize: item.fileSize, optimizedSize: nil,
                        sourceURL: url,
                        status: .failed(error.localizedDescription)
                    ))
                case .idle:
                    break
                }
            }

            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    private func optimizer(for url: URL) -> (any MediaOptimizerProtocol)? {
        guard let utType = UTType(filenameExtension: url.pathExtension) else { return nil }
        return optimizers.first { type(of: $0).supportedContentTypes.contains(utType) }
    }

    private func outputURL(for url: URL) -> URL {
        let dir = url.deletingLastPathComponent()
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        return dir.appendingPathComponent("\(name)_smoosh.\(ext)")
    }
}
