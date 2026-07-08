# Image Optimizer v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add image optimization (PNG, JPEG, GIF) to Smoosh via CLI binaries (oxipng, jpegtran, gifsicle).

**Architecture:** Protocol-driven (`MediaOptimizerProtocol`) with per-format optimizers coordinated by `ImageOptimizationService`. Async progress via `AsyncStream<OptimizationState>`. DropZoneView triggers optimization; HistoryListView shows progress and retry.

**Tech Stack:** Swift, SwiftUI, Process API, Swift Concurrency

## Global Constraints

- macOS 14+ deployment target
- All I/O and process invocation off main thread via async/await
- CLI binaries from PATH (dev) or Bundle Resources (production), never hardcoded paths
- Output saved as `filename_smoosh.ext` next to original
- No third-party Swift packages
- Keep existing patterns (@Observable, .environment injection)

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `smoosh/Services/MediaOptimizerProtocol.swift` | Create | Protocol, state, metrics, error types |
| `smoosh/Services/ProcessRunner.swift` | Create | Async Process wrapper |
| `smoosh/Services/ImageOptimizationService.swift` | Create | Coordinator: routing, I/O, history |
| `smoosh/Services/PNGOptimizer.swift` | Create | OxiPNG invocation |
| `smoosh/Services/JPEGOptimizer.swift` | Create | jpegtran invocation |
| `smoosh/Services/GIFOptimizer.swift` | Create | Gifsicle invocation |
| `smoosh/Helpers/BinaryLocator.swift` | Create | Find CLIs in Bundle or PATH |
| `smoosh/Models/OptimizationItem.swift` | Modify | Add sourceURL, update processing enum |
| `smoosh/Models/AppState.swift` | Modify | Add replaceItem method |
| `smoosh/Views/DropZoneView.swift` | Modify | Trigger optimization, folder support |
| `smoosh/Views/HistoryListView.swift` | Modify | Progress display, retry button |

---

### Task 1: Core Models and Protocol

**Files:**
- Create: `smoosh/Services/MediaOptimizerProtocol.swift`
- Modify: `smoosh/Models/OptimizationItem.swift`
- Modify: `smoosh/Models/AppState.swift`

**Interfaces:**
- Produces: `OptimizationState`, `OptimizationMetrics`, `OptimizationError`, `MediaOptimizerProtocol`, updated `OptimizationItem`, updated `AppState`

- [ ] **Step 1: Create `MediaOptimizerProtocol.swift`**

```swift
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
```

- [ ] **Step 2: Update `OptimizationItem.swift`**

```swift
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
```

- [ ] **Step 3: Update `AppState.swift` — add `replaceItem`**

```swift
import SwiftUI

@Observable
final class AppState {
    var history: [OptimizationItem] = []

    func addItem(_ item: OptimizationItem) {
        history.insert(item, at: 0)
    }

    func replaceItem(_ id: UUID, with item: OptimizationItem) {
        if let index = history.firstIndex(where: { $0.id == id }) {
            history[index] = item
        }
    }

    func removeItems(at offsets: IndexSet) {
        history.remove(atOffsets: offsets)
    }

    func clearHistory() {
        history.removeAll()
    }
}
```

### Task 2: BinaryLocator and ProcessRunner

**Files:**
- Create: `smoosh/Helpers/BinaryLocator.swift`
- Create: `smoosh/Services/ProcessRunner.swift`

**Interfaces:**
- Produces: `BinaryLocator.url(for:) -> URL?`, `ProcessRunner.run(executableURL:arguments:) -> (exitCode: Int32, stdout: String, stderr: String)`

- [ ] **Step 1: Create `BinaryLocator.swift`**

```swift
import Foundation

struct BinaryLocator {
    static func url(for name: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: nil) {
            return url
        }
        return findInPATH(name)
    }

    private static func findInPATH(_ name: String) -> URL? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = [name]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return path.map { URL(fileURLWithPath: $0) }
        } catch {
            return nil
        }
    }
}
```

- [ ] **Step 2: Create `ProcessRunner.swift`**

```swift
import Foundation

struct ProcessRunner {
    static func run(
        executableURL: URL,
        arguments: [String]
    ) async throws -> (exitCode: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let stdout = (try? stdoutPipe.fileHandleForReading.readToEnd()).flatMap {
                    String(data: $0, encoding: .utf8)
                } ?? ""
                let stderr = (try? stderrPipe.fileHandleForReading.readToEnd()).flatMap {
                    String(data: $0, encoding: .utf8)
                } ?? ""
                continuation.resume(returning: (proc.terminationStatus, stdout, stderr))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
```

### Task 3: PNGOptimizer

**Files:**
- Create: `smoosh/Services/PNGOptimizer.swift`

**Interfaces:**
- Conforms to: `MediaOptimizerProtocol` (produces states via AsyncStream)
- Consumes: `BinaryLocator`, `ProcessRunner`, `OptimizationError`

- [ ] **Step 1: Create `PNGOptimizer.swift`**

```swift
import Foundation
import UniformTypeIdentifiers

struct PNGOptimizer: MediaOptimizerProtocol {
    static let supportedContentTypes: [UTType] = [.png]

    func optimize(fileAt inputURL: URL, outputURL: URL) -> AsyncStream<OptimizationState> {
        AsyncStream { continuation in
            continuation.yield(.processing(progress: 0))

            Task {
                guard let binary = BinaryLocator.url(for: "oxipng") else {
                    continuation.yield(.failed(OptimizationError.binaryNotFound("oxipng")))
                    continuation.finish()
                    return
                }

                do {
                    let result = try await ProcessRunner.run(
                        executableURL: binary,
                        arguments: ["-o", "4", "--strip", "all", "--alpha", inputURL.path, "-o", outputURL.path]
                    )

                    if result.exitCode == 0 {
                        let originalSize = (try? FileManager.default.attributesOfItem(atPath: inputURL.path))?[.size] as? Int64 ?? 0
                        let optimizedSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path))?[.size] as? Int64 ?? 0
                        continuation.yield(.completed(metrics: OptimizationMetrics(
                            originalSize: originalSize,
                            optimizedSize: optimizedSize,
                            outputURL: outputURL
                        )))
                    } else {
                        continuation.yield(.failed(OptimizationError.processFailed(
                            exitCode: result.exitCode, stderr: result.stderr
                        )))
                    }
                } catch {
                    continuation.yield(.failed(OptimizationError.ioError(error)))
                }
                continuation.finish()
            }
        }
    }
}
```

### Task 4: JPEGOptimizer

**Files:**
- Create: `smoosh/Services/JPEGOptimizer.swift`

- [ ] **Step 1: Create `JPEGOptimizer.swift`**

```swift
import Foundation
import UniformTypeIdentifiers

struct JPEGOptimizer: MediaOptimizerProtocol {
    static let supportedContentTypes: [UTType] = [.jpeg]

    func optimize(fileAt inputURL: URL, outputURL: URL) -> AsyncStream<OptimizationState> {
        AsyncStream { continuation in
            continuation.yield(.processing(progress: 0))

            Task {
                guard let binary = BinaryLocator.url(for: "jpegtran") else {
                    continuation.yield(.failed(OptimizationError.binaryNotFound("jpegtran")))
                    continuation.finish()
                    return
                }

                do {
                    let result = try await ProcessRunner.run(
                        executableURL: binary,
                        arguments: ["-copy", "none", "-optimize", "-progressive", "-outfile", outputURL.path, inputURL.path]
                    )

                    if result.exitCode == 0 {
                        let originalSize = (try? FileManager.default.attributesOfItem(atPath: inputURL.path))?[.size] as? Int64 ?? 0
                        let optimizedSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path))?[.size] as? Int64 ?? 0
                        continuation.yield(.completed(metrics: OptimizationMetrics(
                            originalSize: originalSize,
                            optimizedSize: optimizedSize,
                            outputURL: outputURL
                        )))
                    } else {
                        continuation.yield(.failed(OptimizationError.processFailed(
                            exitCode: result.exitCode, stderr: result.stderr
                        )))
                    }
                } catch {
                    continuation.yield(.failed(OptimizationError.ioError(error)))
                }
                continuation.finish()
            }
        }
    }
}
```

### Task 5: GIFOptimizer

**Files:**
- Create: `smoosh/Services/GIFOptimizer.swift`

- [ ] **Step 1: Create `GIFOptimizer.swift`**

```swift
import Foundation
import UniformTypeIdentifiers

struct GIFOptimizer: MediaOptimizerProtocol {
    static let supportedContentTypes: [UTType] = [.gif]

    func optimize(fileAt inputURL: URL, outputURL: URL) -> AsyncStream<OptimizationState> {
        AsyncStream { continuation in
            continuation.yield(.processing(progress: 0))

            Task {
                guard let binary = BinaryLocator.url(for: "gifsicle") else {
                    continuation.yield(.failed(OptimizationError.binaryNotFound("gifsicle")))
                    continuation.finish()
                    return
                }

                do {
                    let result = try await ProcessRunner.run(
                        executableURL: binary,
                        arguments: ["--optimize=3", inputURL.path, "-o", outputURL.path]
                    )

                    if result.exitCode == 0 {
                        let originalSize = (try? FileManager.default.attributesOfItem(atPath: inputURL.path))?[.size] as? Int64 ?? 0
                        let optimizedSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path))?[.size] as? Int64 ?? 0
                        continuation.yield(.completed(metrics: OptimizationMetrics(
                            originalSize: originalSize,
                            optimizedSize: optimizedSize,
                            outputURL: outputURL
                        )))
                    } else {
                        continuation.yield(.failed(OptimizationError.processFailed(
                            exitCode: result.exitCode, stderr: result.stderr
                        )))
                    }
                } catch {
                    continuation.yield(.failed(OptimizationError.ioError(error)))
                }
                continuation.finish()
            }
        }
    }
}
```

### Task 6: ImageOptimizationService

**Files:**
- Create: `smoosh/Services/ImageOptimizationService.swift`

**Interfaces:**
- Consumes: `Binarlocator`, `optimizer structs`, `AppState`, `OptimizationItem`
- Produces: `ImageOptimizationService.optimize(fileAt:appState:)` entry point

- [ ] **Step 1: Create `ImageOptimizationService.swift`**

```swift
import Foundation
import UniformTypeIdentifiers

final class ImageOptimizationService {
    static let shared = ImageOptimizationService()

    private let optimizers: [any MediaOptimizerProtocol] = [
        PNGOptimizer(),
        JPEGOptimizer(),
        GIFOptimizer()
    ]

    func optimize(fileAt url: URL, appState: AppState) {
        let fileName = url.lastPathComponent
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64 ?? 0
        let item = OptimizationItem(
            id: UUID(), fileName: fileName, fileSize: fileSize,
            optimizedSize: nil, sourceURL: url, status: .pending
        )
        appState.addItem(item)

        Task {
            let outputURL = self.outputURL(for: url)
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            let tempOutput = tempDir.appendingPathComponent(outputURL.lastPathComponent)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            guard let optimizer = self.optimizer(for: url) else {
                appState.replaceItem(item.id, with: OptimizationItem(
                    id: item.id, fileName: fileName, fileSize: fileSize,
                    optimizedSize: nil, sourceURL: url,
                    status: .failed("Unsupported format")
                ))
                return
            }

            for await state in optimizer.optimize(fileAt: url, outputURL: tempOutput) {
                switch state {
                case .processing(let progress):
                    appState.replaceItem(item.id, with: OptimizationItem(
                        id: item.id, fileName: fileName, fileSize: fileSize,
                        optimizedSize: nil, sourceURL: url,
                        status: .processing(progress)
                    ))
                case .completed(let metrics):
                    let optimizedSize = metrics.optimizedSize
                    if optimizedSize < fileSize {
                        try? FileManager.default.moveItem(at: tempOutput, to: outputURL)
                    } else {
                        try? FileManager.default.removeItem(at: tempOutput)
                    }
                    appState.replaceItem(item.id, with: OptimizationItem(
                        id: item.id, fileName: fileName, fileSize: fileSize,
                        optimizedSize: optimizedSize, sourceURL: url,
                        status: .completed
                    ))
                case .failed(let error):
                    try? FileManager.default.removeItem(at: tempOutput)
                    appState.replaceItem(item.id, with: OptimizationItem(
                        id: item.id, fileName: fileName, fileSize: fileSize,
                        optimizedSize: nil, sourceURL: url,
                        status: .failed(error.localizedDescription)
                    ))
                case .idle:
                    break
                }
            }

            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    private func optimizer(for url: URL) -> (any MediaOptimizerProtocol)? {
        guard let utType = UTType(filenameExtension: url.pathExtension) else { return nil }
        return optimizers.first { type(of: $0).supportedContentTypes.contains(utType) }
    }

    private func outputURL(for url: URL) -> URL {
        let dir = url.deletingLastPathComponent()
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        return dir.appendingPathComponent("\(name)_smoosh.\(ext)")
    }
}
```

### Task 7: UI Integration

**Files:**
- Modify: `smoosh/Views/DropZoneView.swift`
- Modify: `smoosh/Views/HistoryListView.swift`

- [ ] **Step 1: Update DropZoneView — trigger optimization, handle folders**

```swift
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
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadObject(ofClass: NSURL.self) { item, _ in
                guard let url = item as? URL ?? (item as? NSURL) as? URL else { return }
                self.processURL(url)
            }
        }
    }

    private func processURL(_ url: URL) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return }

        if isDir {
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
            while let child = enumerator?.nextObject() as? URL {
                guard !child.hasDirectoryPath else { continue }
                ImageOptimizationService.shared.optimize(fileAt: child, appState: appState)
            }
        } else {
            ImageOptimizationService.shared.optimize(fileAt: url, appState: appState)
        }
    }
}
```

- [ ] **Step 2: Update HistoryListView — progress display, retry button**

Add a retry button for failed items and show progress for processing items. Update the `HistoryRow` `statusBadge` to handle the new `processing(Double)` enum case.

Changed sections in `smoosh/Views/HistoryListView.swift`:

```swift
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
    case .failed:
        HStack(spacing: 4) {
            Badge(text: "Failed", color: .red)
            Button("Retry") {
                // retry logic injected via environment or closure
            }
            .buttonStyle(.plain)
            .font(.caption2)
            .foregroundStyle(.blue)
        }
    }
}
```

But the retry button needs access to the source URL and AppState. The `HistoryRow` is a private struct. I should pass a retry closure or use the environment.

Simplest approach: pass `appState` and `sourceURL` via closure:

```swift
private struct HistoryRow: View {
    let item: OptimizationItem
    let onRetry: (OptimizationItem) -> Void

    ...
}
```

And in the main `HistoryListView`:

```swift
ForEach(appState.history) { item in
    HistoryRow(item: item, onRetry: { item in
        if let url = item.sourceURL {
            ImageOptimizationService.shared.optimize(fileAt: url, appState: appState)
        }
    })
}
```

Full updated `HistoryListView.swift`:

```swift
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
                        HistoryRow(item: item, onRetry: { item in
                            if let url = item.sourceURL {
                                ImageOptimizationService.shared.optimize(fileAt: url, appState: appState)
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
        case .processing:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 10, height: 10)
                Badge(text: "Processing...", color: .blue)
            }
        case .completed:
            Badge(text: item.formattedSavings ?? "Done", color: .green)
        case .failed(let message):
            HStack(spacing: 4) {
                Badge(text: "Failed", color: .red)
                Button("Retry") {
                    onRetry(item)
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundStyle(.blue)
            }
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
```

### Build & Verify

- [ ] **Build the project**

```bash
xcodebuild -project smoosh.xcodeproj -scheme smoosh -destination 'platform=macOS' build
```

Fix any compile errors. Most likely issues: missing `import`, UTType mismatch, enum case pattern matching.

- [ ] **Run and test with a real image**

Drop a .png, .jpg, and .gif file. Verify:
1. History item appears with "Processing..."
2. Completes with "65%" (or similar) badge
3. `_smoosh` file appears next to original
4. Retry works for intentionally broken scenarios
5. Folder drop works (drops all images in the folder)
