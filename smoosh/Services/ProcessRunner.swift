import Foundation

struct ProcessRunner {
    static func run(
        executableURL: URL,
        arguments: [String]
    ) async throws -> (exitCode: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { proc in
                    let stdout = (try? stdoutPipe.fileHandleForReading.readToEnd()).flatMap {
                        String(data: $0, encoding: .utf8)
                    } ?? ""
                    let stderr = (try? stderrPipe.fileHandleForReading.readToEnd()).flatMap {
                        String(data: $0, encoding: .utf8)
                    } ?? ""
                    continuation.resume(returning: (proc.terminationStatus, stdout, stderr))
                }
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            process.terminate()
        }
    }
}
