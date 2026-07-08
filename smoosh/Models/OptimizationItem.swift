import Foundation

struct OptimizationItem: Identifiable {
    let id: UUID
    let fileName: String
    let fileSize: Int64
    let optimizedSize: Int64?
    let sourceURL: URL?
    let status: Status

    enum Status {
        case pending
        case processing(Double)
        case completed
        case failed(String)
    }

    var savingsPercent: Double? {
        guard let optimizedSize else { return nil }
        guard optimizedSize > 0, fileSize > 0 else { return nil }
        return (1.0 - Double(optimizedSize) / Double(fileSize)) * 100
    }

    var formattedSavings: String? {
        guard let pct = savingsPercent else { return nil }
        return String(format: "%.0f%%", pct)
    }
}
