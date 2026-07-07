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
                }
                .padding(.horizontal)
                .padding(.top, 8)

                List {
                    ForEach(appState.history) { item in
                        HistoryRow(item: item)
                    }
                    .onDelete { offsets in
                        appState.removeItems(at: offsets)
                    }
                }
                .listStyle(.plain)
                .frame(minHeight: 100)
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

    private var statusBadge: some View {
        switch item.status {
        case .pending:
            return Badge(text: "Pending", color: .orange)
        case .processing:
            return Badge(text: "Processing...", color: .blue)
        case .completed:
            return Badge(text: item.formattedSavings ?? "Done", color: .green)
        case .failed:
            return Badge(text: "Failed", color: .red)
        }
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
