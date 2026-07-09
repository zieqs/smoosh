import SwiftUI

struct HistoryListView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.history.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                HStack {
                    Text("History")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") {
                        appState.clearHistory()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("clearHistoryButton")
                }
                .padding(.horizontal)
                .padding(.top, 8)

                List {
                    ForEach(appState.history) { item in
                        HistoryRow(item: item, onRetry: { item in
                            if let url = item.sourceURL {
                                OptimizationCoordinator.shared.optimize(fileAt: url, appState: appState)
                            }
                        })
                    }
                    .onDelete { offsets in
                        appState.removeItems(at: offsets)
                    }
                }
                .listStyle(.plain)
                .frame(minHeight: 60, maxHeight: .infinity)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text("No files yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Drop files above to optimize them")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 60)
        .padding()
    }
}

private struct HistoryRow: View {
    let item: OptimizationItem
    let onRetry: (OptimizationItem) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(formattedSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusBadge
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityIdentifier("historyRow-\(item.id.uuidString)")
    }

    private var accessibilityLabelText: String {
        switch item.status {
        case .pending:
            return "\(item.fileName) Pending"
        case .processing(let progress):
            return "\(item.fileName) Processing \(Int(progress * 100)) percent"
        case .completed:
            let savings = item.formattedSavings ?? "Done"
            return "\(item.fileName) Completed \(savings)"
        case .failed:
            return "\(item.fileName) Failed"
        }
    }

    private var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let original = formatter.string(fromByteCount: item.fileSize)
        if let optimized = item.optimizedSize {
            let opt = formatter.string(fromByteCount: optimized)
            return "\(original) → \(opt)"
        }
        return original
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch item.status {
        case .pending:
            Badge(text: "Pending", color: .orange)
        case .processing(let progress):
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 10, height: 10)
                Badge(text: progress > 0 ? "\(Int(progress * 100))%" : "Processing...", color: .blue)
            }
        case .completed:
            Badge(text: item.formattedSavings ?? "Done", color: .green)
        case .failed(let message):
            HStack(spacing: 4) {
                Badge(text: shortError(message), color: .red)
                Button("Retry") {
                    onRetry(item)
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundStyle(.blue)
            }
        }
    }

    private func shortError(_ message: String) -> String {
        if message.hasPrefix("Process exited") { return "Failed" }
        if message.hasPrefix("The operation couldn") { return "Error" }
        if message == "" { return "Failed" }
        return message
    }
}

private struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}
