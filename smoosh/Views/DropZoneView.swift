import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @Environment(AppState.self) private var appState
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isDragging ? "arrow.down.doc.fill" : "arrow.down.doc")
                .font(.system(size: 36, weight: .semibold))
                .foregroundColor(isDragging ? .accentColor : .secondary)
                .symbolEffect(.bounce, value: isDragging)

            VStack(spacing: 4) {
                Text(isDragging ? "Drop to Optimize" : "Drop files here")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Text("Supports Images, videos, and PDFs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 120)
        .contentShape(Rectangle())
        .padding(32)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(isDragging ? Color.accentColor.opacity(0.05) : Color(NSColor.controlBackgroundColor).opacity(0.3))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isDragging ? Color.accentColor : Color.secondary.opacity(0.25),
                    style: StrokeStyle(
                        lineWidth: 2,
                        lineCap: .round,
                        dash: [8, 5]
                    )
                )
        }
        .scaleEffect(isDragging ? 1.02 : 1.0)
        .shadow(color: isDragging ? Color.accentColor.opacity(0.12) : Color.clear, radius: 8, x: 0, y: 4)
        .padding(.horizontal)
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            handleDrop(providers)
            return true
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadObject(ofClass: NSURL.self) { item, _ in
                guard let url = item as? URL ?? (item as? NSURL) as? URL else { return }
                
                let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey])
                let size = Int64(resourceValues?.fileSize ?? 0)

                Task { @MainActor in
                    appState.addItem(OptimizationItem(
                        fileName: url.lastPathComponent,
                        fileSize: size,
                        optimizedSize: nil,
                        status: .pending
                    ))
                }
            }
        }
    }
}
