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
            var stdoutData = Data()
            var stderrData = Data()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    stdoutData.append(data)
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    stderrData.append(data)
                }
            }

            process.terminationHandler = { proc in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                let remaining = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
                stdoutData.append(remaining)
                let errRemaining = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
                stderrData.append(errRemaining)
                continuation.resume(returning: ProcessResult(
                    exitCode: proc.terminationStatus,
                    stdoutData: stdoutData,
                    stderrData: stderrData
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
