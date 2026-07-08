import Foundation
import UniformTypeIdentifiers

struct JPEGOptimizer: MediaOptimizerProtocol {
    static let supportedContentTypes: [UTType] = [.jpeg]

    func optimize(fileAt inputURL: URL, outputURL: URL) -> AsyncStream<OptimizationState> {
        AsyncStream { continuation in
            continuation.yield(.processing(progress: 0))

            Task {
                guard let djpeg = BinaryLocator.url(for: "djpeg"),
                      let cjpeg = BinaryLocator.url(for: "cjpeg") else {
                    continuation.yield(.failed(OptimizationError.binaryNotFound("djpeg or cjpeg")))
                    continuation.finish()
                    return
                }

                do {
                    let tempDir = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    let ppmPath = tempDir.appendingPathComponent("decoded.ppm")
                    FileManager.default.createFile(atPath: ppmPath.path, contents: nil)
                    let ppmHandle = try FileHandle(forWritingTo: ppmPath)

                    let decodeResult: (exitCode: Int32, stderr: String) = try await withCheckedThrowingContinuation { continuation in
                        let proc = Process()
                        proc.executableURL = djpeg
                        proc.arguments = [inputURL.path]
                        proc.standardOutput = ppmHandle

                        let stderrPipe = Pipe()
                        proc.standardError = stderrPipe

                        proc.terminationHandler = { p in
                            try? ppmHandle.close()
                            let stderr = (try? stderrPipe.fileHandleForReading.readToEnd()).flatMap {
                                String(data: $0, encoding: .utf8)
                            } ?? ""
                            continuation.resume(returning: (p.terminationStatus, stderr))
                        }
                        do {
                            try proc.run()
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }

                    guard decodeResult.exitCode == 0 else {
                        try? FileManager.default.removeItem(at: tempDir)
                        continuation.yield(.failed(OptimizationError.processFailed(
                            exitCode: decodeResult.exitCode, stderr: decodeResult.stderr
                        )))
                        continuation.finish()
                        return
                    }

                    let encodeResult = try await ProcessRunner.run(
                        executableURL: cjpeg,
                        arguments: ["-quality", "85", "-optimize", "-progressive", ppmPath.path]
                    )

                    try? FileManager.default.removeItem(at: tempDir)

                    if encodeResult.exitCode == 0 {
                        try encodeResult.stdoutData.write(to: outputURL)
                        let originalSize = (try? FileManager.default.attributesOfItem(atPath: inputURL.path))?[.size] as? Int64 ?? 0
                        let optimizedSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path))?[.size] as? Int64 ?? 0
                        continuation.yield(.completed(metrics: OptimizationMetrics(
                            originalSize: originalSize,
                            optimizedSize: optimizedSize,
                            outputURL: outputURL
                        )))
                    } else {
                        continuation.yield(.failed(OptimizationError.processFailed(
                            exitCode: encodeResult.exitCode, stderr: encodeResult.stderr
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
