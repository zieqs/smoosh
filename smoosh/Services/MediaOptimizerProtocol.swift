import Foundation
import UniformTypeIdentifiers

enum OptimizationState {
    case idle
    case processing(progress: Double)
    case completed(metrics: OptimizationMetrics)
    case failed(Error)
}

struct OptimizationMetrics {
    let originalSize: Int64
    let optimizedSize: Int64
    let outputURL: URL
}

enum OptimizationError: LocalizedError {
    case binaryNotFound(String)
    case unsupportedFormat(String)
    case processFailed(exitCode: Int32, stderr: String)
    case ioError(Error)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let name): return "\(name) not found"
        case .unsupportedFormat(let ext): return "\(ext) is not a supported format"
        case .processFailed(let code, let stderr): return "Process exited (\(code)): \(stderr)"
        case .ioError(let error): return error.localizedDescription
        }
    }
}

protocol MediaOptimizerProtocol {
    func optimize(fileAt inputURL: URL, outputURL: URL) -> AsyncStream<OptimizationState>
    static var supportedContentTypes: [UTType] { get }
}
