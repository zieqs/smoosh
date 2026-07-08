# Smoosh

A free, open-source macOS menu bar application for optimizing images via drag-and-drop.

Built with Swift and SwiftUI, targeting macOS 14+. Licensed under GPL v2.

## Features

- **Menu bar popover** — click the icon to open, drag files onto it, click outside to dismiss
- **Image optimization** — PNG, JPEG, and GIF files
- **Lossy compression** — pngquant (PNG) and MozJPEG (JPEG) for ~50-80% savings
- **Lossless fallback** — OxiPNG for PNGs too large for lossy; jpegtran for huge JPEGs
- **Drag-and-drop** — drop files directly into the popover or onto the menu bar icon
- **Folder support** — drop a folder to optimize all supported images inside it
- **Fade animations** — smooth open/close
- **History** — scrollable list showing savings (e.g. "5.2 MB → 1.8 MB")
- **Retry** — failed items have a retry button

## Future

- **Video optimization** — FFmpeg-based H.264/HEVC transcoding
- **PDF optimization** — native CoreGraphics-based compression

## How It Works

Smoosh bundles open-source CLI compression tools in the app bundle. When you drop a file:

1. The app detects the file type (PNG/JPEG/GIF)
2. Launches the appropriate tool via Swift's `Process` API
3. Applies tuned compression flags for optimal quality vs size
4. Saves the optimized file as `filename_smoosh.ext` next to the original
5. If the optimized file isn't smaller, keeps the original and reports 0% savings

### Image Engines

| Format | Tool | Mode | Typical Savings |
|--------|------|------|-----------------|
| PNG | pngquant | Lossy | 50-80% |
| PNG (fallback) | OxiPNG | Lossless | 5-15% |
| JPEG | MozJPEG cjpeg | Lossy | 30-60% |
| JPEG (fallback) | jpegtran | Lossless | 5-15% |
| GIF | Gifsicle | Lossless | 5-20% |

## Installation

### Option 1: Download Release (coming soon)

Download the latest `.app` from the Releases page, drag to Applications.

### Option 2: Build from Source

Requires Xcode 16+ and macOS 14+.

```bash
git clone https://github.com/zieqs/smoosh.git
cd smoosh
xcodebuild -project smoosh.xcodeproj -scheme smoosh -configuration Release
open "Build/Products/Release/smoosh.app"
```

The Release build is self-contained — all binaries and dylibs are bundled.

### Development Build

```bash
xcodebuild -project smoosh.xcodeproj -scheme smoosh
open "Build/Products/Debug/smoosh.app"
```

The Debug build uses `DYLD_FALLBACK_LIBRARY_PATH` to find dylibs at `/opt/homebrew/lib/`. Install dependencies with:

```bash
brew install pngquant oxipng gifsicle
```

## Project Structure

```
smoosh/
  smoosh.xcodeproj/           # Xcode project
  smoosh/                     # Swift source files
    smooshApp.swift           # App entry point
    AppDelegate.swift         # NSApplication delegate
    ContentView.swift         # Root popover view
    Assets.xcassets/          # App icons
    Services/
      MediaOptimizerProtocol.swift  # Protocol, state, metrics, errors
      ProcessRunner.swift           # Async Process wrapper
      ImageOptimizationService.swift # Coordinator/router
      PNGOptimizer.swift
      JPEGOptimizer.swift
      GIFOptimizer.swift
    Helpers/
      BinaryLocator.swift    # Find CLIs in bundle or PATH
    Models/
      AppState.swift         # Observable shared state
      OptimizationItem.swift # History item model
    Views/
      DropZoneView.swift     # Drag-and-drop landing zone
      HistoryListView.swift  # Optimization history
      BottomButtonsView.swift # Preferences, Tip Jar, Quit
    StatusBar/
      StatusBarController.swift # NSStatusItem + NSPanel management
      DragOverlayView.swift     # NSDraggingDestination on menu bar icon
    Environment/
      ClosePanelAction.swift    # Environment key for panel actions
  resources/
    release-binaries/          # Pre-modified binaries for Release builds
    release-dylibs/            # Bundled dylibs for Release builds
  docs/
    CONTEXT.md                 # Project specification
    AGENTS.md                  # Agent instructions
```

## Architecture

- **`MediaOptimizerProtocol`** — Each format implements this protocol, returning an `AsyncStream<OptimizationState>` for progress reporting
- **`ImageOptimizationService`** — Singleton coordinator that detects format, routes to the right optimizer, manages temp files, and updates AppState
- **`ProcessRunner`** — Async wrapper around `Process()` with `readabilityHandler` for streaming stdout/stderr
- **`NSStatusItem` + `NSPanel`** — Custom menu bar popover (not SwiftUI `MenuBarExtra`) for fine-grained control over positioning, animation, and drag handling

## Attribution

Smoosh bundles open-source software. Licenses for each tool are included in their respective source distributions.

- [pngquant](https://pngquant.org/) — GPL v3
- [OxiPNG](https://github.com/shssoichiro/oxipng) — MIT
- [MozJPEG](https://github.com/mozilla/mozjpeg) — BSD-style
- [Gifsicle](https://www.lcdf.org/gifsicle/) — GPL v2
- [FFmpeg](https://ffmpeg.org/) — LGPL/GPL (future)

## License

Smoosh itself is licensed under **GNU General Public License v2 (GPL v2)**.

## Support

If you find this useful, consider supporting development via [GitHub Sponsors](https://github.com/sponsors/zieqs) or [Ko-fi](https://ko-fi.com/zieqs).
