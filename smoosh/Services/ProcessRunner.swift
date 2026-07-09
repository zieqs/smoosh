import Foundation

struct ProcessResult {
    let exitCode: Int32
    let stdoutData: Data
    let stderrData: Data
    let timedOut: Bool

    var stdout: String { String(data: stdoutData, encoding: .utf8) ?? "" }
    var stderr: String { String(data: stderrData, encoding: .utf8) ?? "" }

    static func timeout() -> ProcessResult {
        ProcessResult(exitCode: -1, stdoutData: Data(), stderrData: Data(), timedOut: true)
    }
}

struct ProcessTimeoutError: Error, LocalizedError {
    let executableName: String
    let timeoutSeconds: TimeInterval

    var errorDescription: String? {
        "Timed out after \(Int(timeoutSeconds))s"
    }
}

struct ProcessRunner {
    static func run(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval? = nil,
        progressHandler: ((Data) -> Void)? = nil
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
            let stdoutData = LockedData()
            let stderrData = LockedData()
            var timeoutWorkItem: DispatchWorkItem?
            var hasResumed = false
            let lock = NSLock()

            let finish = { (result: ProcessResult) in
                lock.lock()
                defer { lock.unlock() }
                guard !hasResumed else { return }
                hasResumed = true
                timeoutWorkItem?.cancel()
                continuation.resume(returning: result)
            }

            if let timeout = timeout {
                let workItem = DispatchWorkItem {
                    process.terminate()
                    let remaining = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
                    stderrData.append(remaining)
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    let result = ProcessResult(
                        exitCode: -1,
                        stdoutData: stdoutData.data,
                        stderrData: stderrData.data,
                        timedOut: true
                    )
                    finish(result)
                }
                timeoutWorkItem = workItem
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: workItem)
            }

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
                    progressHandler?(data)
                }
            }

            process.terminationHandler = { proc in
                let exitCode = proc.terminationStatus
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                let outData = stdoutData.data
                let errData = stderrData.data
                let remaining = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
                let errRemaining = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
                let result = ProcessResult(
                    exitCode: exitCode,
                    stdoutData: outData + remaining,
                    stderrData: errData + errRemaining,
                    timedOut: false
                )
                finish(result)
            }
            do {
                try process.run()
            } catch {
                timeoutWorkItem?.cancel()
                continuation.resume(throwing: error)
            }
        }
    }
}

private final class LockedData: @unchecked Sendable {
    private nonisolated(unsafe) var storage = Data()
    private let lock = NSLock()

    nonisolated var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    nonisolated func append(_ data: Data) {
        lock.lock()
        storage.append(data)
        lock.unlock()
    }
}
