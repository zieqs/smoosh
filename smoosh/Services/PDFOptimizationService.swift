import Foundation
import UniformTypeIdentifiers

final class PDFOptimizationService {
    static let shared = PDFOptimizationService()

    private init() {}

    func optimize(fileAt url: URL, appState: AppState) {
        let item = OptimizationItem(
            id: UUID(), fileName: url.lastPathComponent,
            fileSize: (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64 ?? 0,
            optimizedSize: nil, sourceURL: url, status: .pending
        )

        let outputURL = url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + "_smoosh.pdf")

        Task { @MainActor in
            appState.addItem(item)

            guard let qpdf = BinaryLocator.url(for: "qpdf") else {
                appState.replaceItem(item.id, with: OptimizationItem(
                    id: item.id, fileName: url.lastPathComponent,
                    fileSize: item.fileSize, optimizedSize: nil,
                    sourceURL: url, status: .failed("qpdf not found")
                ))
                return
            }

            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            let tempOutput = tempDir.appendingPathComponent(outputURL.lastPathComponent)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            do {
                appState.replaceItem(item.id, with: OptimizationItem(
                    id: item.id, fileName: url.lastPathComponent,
                    fileSize: item.fileSize, optimizedSize: nil,
                    sourceURL: url, status: .processing(0)
                ))

                let result = try await ProcessRunner.run(
                    executableURL: qpdf,
                    arguments: [
                        "--object-streams=generate",
                        "--compress-streams=y",
                        "--recompress-flate",
                        url.path,
                        tempOutput.path
                    ]
                )

                if result.exitCode == 0 {
                    let optimizedSize = (try? FileManager.default.attributesOfItem(atPath: tempOutput.path))?[.size] as? Int64 ?? 0
                    let isSmaller = optimizedSize < item.fileSize

                    if isSmaller {
                        try? FileManager.default.moveItem(at: tempOutput, to: outputURL)
                    } else {
                        try? FileManager.default.removeItem(at: tempOutput)
                    }

                    appState.replaceItem(item.id, with: OptimizationItem(
                        id: item.id, fileName: url.lastPathComponent,
                        fileSize: item.fileSize,
                        optimizedSize: isSmaller ? optimizedSize : item.fileSize,
                        sourceURL: url, status: .completed
                    ))
                } else {
                    try? FileManager.default.removeItem(at: tempOutput)
                    appState.replaceItem(item.id, with: OptimizationItem(
                        id: item.id, fileName: url.lastPathComponent,
                        fileSize: item.fileSize, optimizedSize: nil,
                        sourceURL: url,
                        status: .failed(result.exitCode > 128 ? "Out of memory" : "Optimization failed")
                    ))
                }
            } catch {
                try? FileManager.default.removeItem(at: tempOutput)
                appState.replaceItem(item.id, with: OptimizationItem(
                    id: item.id, fileName: url.lastPathComponent,
                    fileSize: item.fileSize, optimizedSize: nil,
                    sourceURL: url, status: .failed(error.localizedDescription)
                ))
            }

            try? FileManager.default.removeItem(at: tempDir)
        }
    }
}
