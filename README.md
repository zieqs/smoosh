# Smoosh

A free, open-source macOS menu bar application for optimizing images, videos, and PDFs via drag-and-drop.

Built with Swift and SwiftUI, targeting macOS 14+. Licensed under GPL v2.

## Features

- **Menu bar popover** — click the icon to open, drag files onto it, click outside to dismiss
- **Image optimization** — PNG, JPEG, and GIF compression
- **Lossy + lossless fallback** — aggressive savings most of the time, safe fallback for huge files
- **Drag-and-drop anywhere** — drop onto the popover or directly onto the menu bar icon
- **Folder support** — drop a folder to optimize all supported files inside it
- **History list** — see what was optimized, by how much, and retry if something failed
- **Smooth animations** — fade in/out, no sudden pop-in

## How It Works

Smoosh bundles open-source CLI compression tools inside the app. When you drop a file:

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

Video (FFmpeg) and PDF (CoreGraphics) engines coming.

## Installation

### Download

Grab the latest `.app` from the [Releases](https://github.com/zieqs/smoosh/releases) page, drag to Applications, and launch. The app lands in your menu bar.

### Build from Source

Requires Xcode 16+ and macOS 14+.

```bash
git clone https://github.com/zieqs/smoosh.git
cd smoosh
xcodebuild -project smoosh.xcodeproj -scheme smoosh -configuration Release
open "Build/Products/Release/smoosh.app"
```

The Release build is fully self-contained — all binaries and libraries are bundled in the `.app`.

## Architecture

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
    release-binaries/          # Pre-linked binaries for Release builds
    release-dylibs/            # Bundled dylibs for Release builds
  docs/
    CONTEXT.md                 # Project specification
    AGENTS.md                  # Agent instructions
```

- **`MediaOptimizerProtocol`** — Each format implements this, returning an `AsyncStream<OptimizationState>` for progress
- **`ImageOptimizationService`** — Singleton coordinator: detects format, routes to the right optimizer, manages temp files, updates AppState
- **`ProcessRunner`** — Async wrapper around `Process()` with `readabilityHandler` for streaming stdout/stderr
- **`NSStatusItem` + `NSPanel`** — Custom menu bar popover (not SwiftUI `MenuBarExtra`) for fine-grained positioning, animation, and drag handling

## Attribution

Smoosh bundles open-source software:

- [pngquant](https://pngquant.org/) — GPL v3
- [OxiPNG](https://github.com/shssoichiro/oxipng) — MIT
- [MozJPEG](https://github.com/mozilla/mozjpeg) — BSD-style
- [Gifsicle](https://www.lcdf.org/gifsicle/) — GPL v2

## License

Smoosh is free software licensed under the **GNU General Public License v2**.

## Support

If you find Smoosh useful, consider supporting development:
- [GitHub Sponsors](https://github.com/sponsors/zieqs)
- [Ko-fi](https://ko-fi.com/zieqs)
