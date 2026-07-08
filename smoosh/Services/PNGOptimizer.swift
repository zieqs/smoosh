import Foundation
import UniformTypeIdentifiers

struct PNGOptimizer: MediaOptimizerProtocol {
    static let supportedContentTypes: [UTType] = [.png]

    func optimize(fileAt inputURL: URL, outputURL: URL) -> AsyncStream<OptimizationState> {
        AsyncStream { continuation in
            continuation.yield(.processing(progress: 0))

            Task {
                guard let pngquant = BinaryLocator.url(for: "pngquant"),
                      let oxipng = BinaryLocator.url(for: "oxipng") else {
                    continuation.yield(.failed(OptimizationError.binaryNotFound("pngquant or oxipng")))
                    continuation.finish()
                    return
                }

                do {
                    let result = try await ProcessRunner.run(
                        executableURL: pngquant,
                        arguments: ["--quality=65-80", "--speed", "1", "--output", outputURL.path, inputURL.path]
                    )

                    if result.exitCode == 0 {
                        let originalSize = (try? FileManager.default.attributesOfItem(atPath: inputURL.path))?[.size] as? Int64 ?? 0
                        let optimizedSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path))?[.size] as? Int64 ?? 0
                        continuation.yield(.completed(metrics: OptimizationMetrics(
                            originalSize: originalSize,
                            optimizedSize: optimizedSize,
                            outputURL: outputURL
                        )))
                        continuation.finish()
                        return
                    }

                    if result.exitCode == 99 {
                        try FileManager.default.copyItem(at: inputURL, to: outputURL)

                        let oxiResult = try await ProcessRunner.run(
                            executableURL: oxipng,
                            arguments: ["-o", "4", "--strip", "all", "--alpha", outputURL.path]
                        )

                        if oxiResult.exitCode == 0 {
                            let originalSize = (try? FileManager.default.attributesOfItem(atPath: inputURL.path))?[.size] as? Int64 ?? 0
                            let optimizedSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path))?[.size] as? Int64 ?? 0
                            continuation.yield(.completed(metrics: OptimizationMetrics(
                                originalSize: originalSize,
                                optimizedSize: optimizedSize,
                                outputURL: outputURL
                            )))
                        } else {
                            continuation.yield(.failed(OptimizationError.processFailed(
                                exitCode: oxiResult.exitCode, stderr: oxiResult.stderr
                            )))
                        }
                        continuation.finish()
                        return
                    }

                    continuation.yield(.failed(OptimizationError.processFailed(
                        exitCode: result.exitCode, stderr: result.stderr
                    )))
                } catch {
                    continuation.yield(.failed(OptimizationError.ioError(error)))
                }
                continuation.finish()
            }
        }
    }
}
