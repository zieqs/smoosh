# Smoosh — AGENTS.md

## Project Overview

Smoosh is a free, open-source macOS menu bar application for optimizing images, videos, and PDFs via drag-and-drop. Licensed under GPL v2. Monetized via an integrated Tip Jar (GitHub Sponsors / Ko-fi).

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Swift |
| UI Framework | SwiftUI (`MenuBarExtra`, targeting macOS 14+) |
| Concurrency | Swift Concurrency (`async/await`, `Task`, `AsyncSequence`) |
| Image Engine | Bundled CLIs: `pngquant` / `OxiPNG` (PNG), `MozJPEG` (JPEG), `Gifsicle` (GIF) — via `Process` API |
| Video Engine | Bundled `ffmpeg` CLI — via `Process` API, parse `stderr` for progress |
| PDF Engine | Native: `CoreGraphics` / `CGPDFDocument` / `CGPDFContext` / `PDFKit` — no external binaries |

## Project Structure

```
smoosh/
  smoosh.xcodeproj/           # Xcode project
  smoosh/                     # Swift source files
    smooshApp.swift           # App entry point (convert to MenuBarExtra)
    ContentView.swift         # Main drop-zone UI
    Assets.xcassets/          # App icons, accent colors
    Services/                 # [TO CREATE] Optimization service classes
    Models/                   # [TO CREATE] State models, metrics
    Resources/                # [TO CREATE] Bundled CLI binaries (copied in Build Phases)
  docs/
    CONTEXT.md                # Full project specification
    AGENTS.md                 # This file — agent instructions
```

## Processing Engines

### Images
- **PNG:** `pngquant` (lossy) or `OxiPNG` (lossless) — bundled in `Contents/Resources/`
- **JPEG:** `MozJPEG` (as `cjpeg`) — bundled
- **GIF:** `Gifsicle` — bundled
- Execution: `Process()` with tuned flags. Track stdout/stderr.

### Video
- **Engine:** Bundled `ffmpeg` binary
- **Strategy:** Transcode to H.264 or HEVC (H.265) with CRF target; audio to AAC
- **Progress:** Parse FFmpeg `stderr` time/duration tokens for percentage
- **No third-party Swift wrappers** — use native `Process()` only

### PDF
- **Engine:** Native Apple frameworks only
- **Strategy:** Load via `CGPDFDocument`, re-export via `CGPDFContext` with lossy JPEG compression on bitmaps, downsample to 150 DPI

## Agent Rules

1. **Concurrency:** All file I/O, process invocation, and rendering must run off the main thread. Use modern Swift Concurrency (`async/await`, `Task`, `AsyncSequence`). Never use DispatchQueue for new code.

2. **Protocol-driven services:** Each optimizer must conform to a unified `MediaOptimizerProtocol` with an async state stream:
   - `idle`
   - `processing(percentage: Double)`
   - `completed(metrics: OptimizationMetrics)`
   - `failed(error: Error)`

3. **No third-party wrappers:** For FFmpeg or any CLI tool, use native Swift `Process()` only. No Obj-C or Swift bridging wrappers.

4. **Safe temp files:** Use sandboxed temporary directories (`FileManager.default.temporaryDirectory`). Never write to user-visible directories without explicit output selection.

5. **Bundle CLI binaries:** All CLI tools go in `Contents/Resources/` and are copied via Xcode Build Phases. Ensure they are code-signed and notarized for distribution.

6. **UI patterns:**
   - `MenuBarExtra` scene style (not `WindowGroup`)
   - Drag-and-drop zone accepting files/URLs
   - Progress bars / indeterminate spinners during processing
   - Scrollable history list showing "5.2 MB → 1.8 MB (-65%)" stats
   - Tip Jar button at bottom → `NSWorkspace.shared.open()` to external URL

7. **Avoid adding comments** to code unless the logic genuinely requires explanation. Let the code speak.

## Coding Standards

### Swift Style
- Use explicit types where they improve clarity; prefer type inference otherwise.
- One class/struct per file, named after the type.
- Prefer `struct` over `class` unless reference semantics are required.
- Use Swift-native `Error` enums with `LocalizedError` conformance.

### Concurrency
- `async` functions for all service APIs.
- `AsyncSequence` or `AsyncStream` for progress/state updates from services.
- `Task { ... }` for fire-and-forget work from the UI layer.
- `@MainActor` on View types and UI-updating methods.

### File Organization
- `Services/ImageOptimizationService.swift`
- `Services/VideoOptimizationService.swift`
- `Services/PDFOptimizationService.swift`
- `Models/OptimizationMetrics.swift`
- `Models/OptimizationState.swift`
- `Views/` — SwiftUI views if ContentView grows

### Naming
- Services: `ImageOptimizationService`, `VideoOptimizationService`, `PDFOptimizationService`
- Protocol: `MediaOptimizerProtocol`
- States: `OptimizationState` enum
- Metrics: `OptimizationMetrics` struct (`originalSize`, `optimizedSize`, `savingsPercent`, `format`)

## Build & Run

- Open `smoosh.xcodeproj` in Xcode 16+.
- Deployment target: macOS 14+.
- Bundle identifier: `com.zieqs.smoosh`.
- CLI binaries must be added to `Copy Files` Build Phase → `Resources` destination.
- Code signing and notarization required for distribution (not for debug builds).
- No external package dependencies currently — CLI binaries are vendored.

## Attribution & License

- Licensed under **GNU General Public License v2 (GPL v2)**.
- Bundled open-source tools retain their own licenses. Include attribution in app About dialog and README.
- Tip Jar must link to external platforms (GitHub Sponsors / Ko-fi), not process payments in-app.
