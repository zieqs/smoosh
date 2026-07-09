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

                Text("Supports images, PDFs, and video")
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
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [8, 5])
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
        .accessibilityIdentifier("dropZone")
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadObject(ofClass: NSURL.self) { item, _ in
                guard let url = item as? URL ?? (item as? NSURL) as? URL else { return }
                Task { @MainActor in
                    self.processURL(url)
                }
            }
        }
    }

    private func processURL(_ url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }

        if isDirectory.boolValue {
            let supportedTypes: [UTType] = [.png, .jpeg, .gif, .pdf, .mpeg4Movie, .quickTimeMovie, .movie]
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
            while let child = enumerator?.nextObject() as? URL {
                guard !child.hasDirectoryPath else { continue }
                guard let type = UTType(filenameExtension: child.pathExtension),
                      supportedTypes.contains(type) else { continue }
                OptimizationCoordinator.shared.optimize(fileAt: child, appState: appState)
            }
        } else {
            OptimizationCoordinator.shared.optimize(fileAt: url, appState: appState)
        }
    }
}
