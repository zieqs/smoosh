import Foundation
import UniformTypeIdentifiers

struct JPEGOptimizer: MediaOptimizerProtocol {
    static let supportedContentTypes: [UTType] = [.jpeg]

    func optimize(fileAt inputURL: URL, outputURL: URL) -> AsyncStream<OptimizationState> {
        AsyncStream { continuation in
            continuation.yield(.processing(progress: 0))

            Task {
                guard let djpeg = BinaryLocator.url(for: "djpeg"),
                      let cjpeg = BinaryLocator.url(for: "cjpeg"),
                      let jpegtran = BinaryLocator.url(for: "jpegtran") else {
                    continuation.yield(.failed(OptimizationError.binaryNotFound("djpeg, cjpeg, or jpegtran")))
                    continuation.finish()
                    return
                }

                let originalSize = (try? FileManager.default.attributesOfItem(atPath: inputURL.path))?[.size] as? Int64 ?? 0

                do {
                    let shell = Process()
                    shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
                    let script = "\"\(djpeg.path)\" \"\(inputURL.path)\" 2>/dev/null | \"\(cjpeg.path)\" -quality 85 -optimize -progressive > \"\(outputURL.path)\""
                    shell.arguments = ["-c", script]

                    var env = ProcessInfo.processInfo.environment
                    let libPaths = ["/opt/homebrew/lib", Bundle.main.resourcePath].compactMap { $0 }.joined(separator: ":")
                    env["DYLD_FALLBACK_LIBRARY_PATH"] = libPaths
                    shell.environment = env

                    let stderrPipe = Pipe()
                    shell.standardError = stderrPipe

                    let result: (exitCode: Int32, stderr: String) = try await withCheckedThrowingContinuation { continuation in
                        shell.terminationHandler = { p in
                            let stderr = (try? stderrPipe.fileHandleForReading.readToEnd()).flatMap {
                                String(data: $0, encoding: .utf8)
                            } ?? ""
                            continuation.resume(returning: (p.terminationStatus, stderr))
                        }
                        do {
                            try shell.run()
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }

                    let optimizedSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path))?[.size] as? Int64 ?? 0

                    if result.exitCode == 0, optimizedSize > 0 {
                        continuation.yield(.completed(metrics: OptimizationMetrics(
                            originalSize: originalSize,
                            optimizedSize: optimizedSize,
                            outputURL: outputURL
                        )))
                        continuation.finish()
                        return
                    }

                    try? FileManager.default.removeItem(at: outputURL)

                    let fallbackResult = try await ProcessRunner.run(
                        executableURL: jpegtran,
                        arguments: ["-copy", "none", "-optimize", "-progressive", "-outfile", outputURL.path, inputURL.path]
                    )

                    let fallbackSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path))?[.size] as? Int64 ?? 0

                    if fallbackResult.exitCode == 0, fallbackSize > 0 {
                        continuation.yield(.completed(metrics: OptimizationMetrics(
                            originalSize: originalSize,
                            optimizedSize: fallbackSize,
                            outputURL: outputURL
                        )))
                    } else {
                        try? FileManager.default.removeItem(at: outputURL)
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
