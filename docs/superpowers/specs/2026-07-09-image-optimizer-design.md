# Image Optimizer — v1 Design Spec

## Overview

Build an image optimization engine for Smoosh using bundled CLI binaries orchestrated via Swift Concurrency. Supplements the existing drag-and-drop UI with real file processing: progress reporting, savings metrics, error handling, and output management.

## Supported Formats

| Format | Tool | Mode | Flags |
|---|---|---|---|
| PNG | OxiPNG | Lossless | `-o 4 --strip all --alpha "{input}" -o "{output}"` |
| JPEG | MozJPEG `jpegtran` | Lossless | `-copy none -optimize -progressive -outfile "{output}" "{input}"` |
| GIF | Gifsicle | Lossless | `--optimize=3 "{input}" > "{output}"` |

## Core Protocol & Models

### `MediaOptimizerProtocol`

```swift
protocol MediaOptimizerProtocol {
    func optimize(fileAt inputURL: URL, outputURL: URL) -> AsyncStream<OptimizationState>
    static var supportedContentTypes: [UTType] { get }
}
```

### `OptimizationState`

```swift
enum OptimizationState {
    case idle
    case processing(progress: Double)
    case completed(metrics: OptimizationMetrics)
    case failed(Error)
}
```

### `OptimizationMetrics`

```swift
struct OptimizationMetrics {
    let originalSize: Int64
    let optimizedSize: Int64
    let outputURL: URL
}
```

### Error Type

```swift
enum OptimizationError: Error, LocalizedError {
    case binaryNotFound(String)
    case unsupportedFormat(String)
    case processFailed(exitCode: Int32, stderr: String)
    case outputIsLarger
    case ioError(Error)
}
```

## Per-Format Optimizers

Three small classes, each conforming to `MediaOptimizerProtocol`:

- **`PNGOptimizer`** — shells out to `oxipng`
- **`JPEGOptimizer`** — shells out to `jpegtran`
- **`GIFOptimizer`** — shells out to `gifsicle`

Each uses a shared `ProcessRunner` helper to handle `Process()` creation, stdout/stderr capture, and cancellation. The state stream emits:
- `.processing(progress: 0)` at launch
- `.processing(progress: 1)` on non-zero exit
- `.completed(metrics:)` on zero exit
- `.failed(error:)` on error or non-zero exit

## Service Orchestration: `ImageOptimizationService`

1. Detect format from the dropped URL via `UTType(filenameExtension:)`
2. Pick the matching optimizer from a registry `[PNGOptimizer.self, JPEGOptimizer.self, GIFOptimizer.self]`
3. Generate output path: `inputURL.deletingPathExtension()` + `_smoosh` + `inputURL.pathExtension` — inserts before the last extension component. E.g., `photo.png` → `photo_smoosh.png`, `archive.tar.gz` → `archive.tar_smoosh.gz`.
4. Create a unique temp directory under `FileManager.default.temporaryDirectory`
5. Run the optimizer into a temp file
6. Compare sizes:
   - If optimized < original: move temp to final output path, emit `completed(metrics)`
   - If optimized >= original: discard temp, keep original, emit `completed(metrics)` with `optimizedSize == originalSize` (savings = 0%)
7. Clean up temp directory
8. Update the corresponding `OptimizationItem` in `AppState` as states arrive

## Folder Support

When a folder is dropped, recurse and find all images matching supported types (png, jpg/jpeg, gif), then optimize each independently. Each file gets its own history item. Progress updates are scoped to the current file being processed.

## Output Strategy

- Saved in the same directory as the original
- Suffix: `_smoosh` (e.g., `photo.png` → `photo_smoosh.png`)
- Hardcoded for v1 (no user preference)
- If optimized file is NOT smaller, discard it and keep original

## UI Integration

- `DropZoneView` creates a pending `OptimizationItem` on drop, then calls `ImageOptimizationService.optimize(fileAt:)`
- Service updates the item in `AppState`:
  - State changes trigger SwiftUI observation
  - UI shows indeterminate spinner or progress bar during processing
  - Completed items show "5.2 MB → 1.8 MB (-65%)" style savings
- Failed items show a **retry button** that re-runs the optimization
- History list (`HistoryListView`) displays the updated items

## Error Handling

- Format not recognized → emit `.failed` with `unsupportedFormat`
- CLI binary not found → emit `.failed` with `binaryNotFound`
- CLI process exits non-zero → capture stderr, emit `.failed` with `processFailed`
- Optimized file larger → not a failure; emit `.completed` with same-size metrics (0% savings)
- Temp file I/O errors → emit `.failed` with `ioError`

## Binary Setup

### Development
- Reference tools from `/opt/homebrew/bin/` using `Bundle.main.url(forResource: withExtension:)` with a fallback to `Process` PATH lookup
- `BinaryLocator` helper encapsulates the lookup logic
- Requires `brew install oxipng gifsicle` (jpegtran is already present)

### Production
- Download official macOS ARM64/x86_64 builds of oxipng, jpegtran (from mozjpeg), and gifsicle
- Add to an Xcode `Resources/` group
- Copy to `Contents/Resources/` via Build Phases
- Code-sign during app notarization

## Files to Create/Modify

### New Files
```
smoosh/Services/MediaOptimizerProtocol.swift
smoosh/Services/ProcessRunner.swift
smoosh/Services/ImageOptimizationService.swift
smoosh/Services/PNGOptimizer.swift
smoosh/Services/JPEGOptimizer.swift
smoosh/Services/GIFOptimizer.swift
smoosh/Models/OptimizationState.swift
smoosh/Models/OptimizationMetrics.swift
smoosh/Helpers/BinaryLocator.swift
```

### Modified Files
```
smoosh/Models/OptimizationItem.swift          — add retry support
smoosh/Models/AppState.swift                  — add optimization pipeline hook
smoosh/Views/DropZoneView.swift               — wire up optimization after drop
smoosh/Views/HistoryListView.swift            — show progress, retry button
```

## Out of Scope for v1

- WebP, AVIF, HEIC support
- User-customizable output suffix
- Batch summary (total savings across batch)
- Background processing queue / pause button
- Binary code signing and notarization setup
