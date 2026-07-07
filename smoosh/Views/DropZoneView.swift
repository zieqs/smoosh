import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @Environment(AppState.self) private var appState
    @State private var isDragging = false

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(style: StrokeStyle(lineWidth: 2, dash: [6]))
            .foregroundStyle(isDragging ? Color.accentColor : Color.secondary)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc")
                        .font(.largeTitle)
                        .foregroundStyle(isDragging ? Color.accentColor : Color.secondary)
                    Text("Drop files here")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Images, videos, and PDFs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 130)
            .padding()
            .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
                handleDrop(providers)
                return true
            }
            .animation(.easeInOut(duration: 0.2), value: isDragging)
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadObject(ofClass: NSURL.self) { item, _ in
                guard let url = item as? URL ?? (item as? NSURL) as? URL
                else { return }

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
