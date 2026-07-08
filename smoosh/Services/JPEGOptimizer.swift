import Foundation
import UniformTypeIdentifiers

struct JPEGOptimizer: MediaOptimizerProtocol {
    static let supportedContentTypes: [UTType] = [.jpeg]

    func optimize(fileAt inputURL: URL, outputURL: URL) -> AsyncStream<OptimizationState> {
        AsyncStream { continuation in
            continuation.yield(.processing(progress: 0))

            Task {
                guard let binary = BinaryLocator.url(for: "jpegtran") else {
                    continuation.yield(.failed(OptimizationError.binaryNotFound("jpegtran")))
                    continuation.finish()
                    return
                }

                do {
                    let result = try await ProcessRunner.run(
                        executableURL: binary,
                        arguments: ["-copy", "none", "-optimize", "-progressive", "-outfile", outputURL.path, inputURL.path]
                    )

                    if result.exitCode == 0 {
                        let originalSize = (try? FileManager.default.attributesOfItem(atPath: inputURL.path))?[.size] as? Int64 ?? 0
                        let optimizedSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path))?[.size] as? Int64 ?? 0
                        continuation.yield(.completed(metrics: OptimizationMetrics(
                            originalSize: originalSize,
                            optimizedSize: optimizedSize,
                            outputURL: outputURL
                        )))
                    } else {
                        continuation.yield(.failed(OptimizationError.processFailed(
                            exitCode: result.exitCode, stderr: result.stderr
                        )))
                    }
                } catch {
                    continuation.yield(.failed(OptimizationError.ioError(error)))
                }
                continuation.finish()
            }
        }
    }
}
