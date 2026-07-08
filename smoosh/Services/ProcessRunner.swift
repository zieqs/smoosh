import Foundation

struct ProcessResult {
    let exitCode: Int32
    let stdoutData: Data
    let stderrData: Data

    var stdout: String { String(data: stdoutData, encoding: .utf8) ?? "" }
    var stderr: String { String(data: stderrData, encoding: .utf8) ?? "" }
}

struct ProcessRunner {
    static func run(
        executableURL: URL,
        arguments: [String]
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let stdout = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
                let stderr = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
                continuation.resume(returning: ProcessResult(
                    exitCode: proc.terminationStatus,
                    stdoutData: stdout,
                    stderrData: stderr
                ))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
