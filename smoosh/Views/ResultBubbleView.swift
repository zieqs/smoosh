import SwiftUI

struct ResultBubbleView: View {
    let item: OptimizationItem
    let onDismiss: () -> Void
    let onAggressive: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.fileName)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)

            switch item.status {
            case .pending, .processing:
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 10, height: 10)
                    Text("Optimizing...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .completed:
                Text("\(ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file)) → \(ByteCountFormatter.string(fromByteCount: item.optimizedSize ?? item.fileSize, countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .center, spacing: 4) {
                    if let savings = item.formattedSavings {
                        Text(savings)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(savings == "0%" ? Color.secondary : Color.green)
                    }
                    Spacer()
                }

            case .failed(let message):
                Text(shortError(message))
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 8) {
                if item.isPDF {
                    Button("Aggressive PDF") {
                        onAggressive()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer()

                Button("Dismiss") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
    }

    private func shortError(_ message: String) -> String {
        if message == "" { return "Failed" }
        return message
    }
}
