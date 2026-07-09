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

        var env = ProcessInfo.processInfo.environment
        let libPaths = ["/opt/homebrew/lib", Bundle.main.resourcePath].compactMap { $0 }.joined(separator: ":")
        env["DYLD_FALLBACK_LIBRARY_PATH"] = libPaths
        process.environment = env

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
                let exitCode = proc.terminationStatus
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                let outData = stdoutData
                let errData = stderrData
                let remaining = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
                let errRemaining = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
                let result = ProcessResult(
                    exitCode: exitCode,
                    stdoutData: outData + remaining,
                    stderrData: errData + errRemaining
                )
                DispatchQueue.main.async {
                    continuation.resume(returning: result)
                }
            }
            do {
                try process.run()
            } catch {
                DispatchQueue.main.async {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
