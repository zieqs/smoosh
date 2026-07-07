### Master Project Specification: Multi-Format Media Optimizer (macOS Menu Bar)

#### 1. Project Vision & Licensing
- **Goal:** A free, lightweight, open-source macOS menu bar application allowing users to quickly optimize images, videos, and PDFs via intuitive drag-and-drop.
- **License:** GNU General Public License v2 (GPL v2). The entire codebase will be hosted publicly on GitHub.
- **Monetization:** Completely free tier with an integrated "Tip Jar" (linking to external platforms like GitHub Sponsors or Ko-fi) present both in the GitHub repository and the app's UI layer.

#### 2. Architecture Overview
The app will be built using a hybrid processing architecture: utilizing native macOS core frameworks for system-supported formats to keep the app lightweight, and bundling verified open-source Command Line Interface (CLI) binaries to handle complex cross-platform compression logic.

- **App Framework:** Swift, SwiftUI (Targeting macOS 14+ / Sonoma or later), configured cleanly as a `MenuBarExtra` system application.
- **Concurrency:** All heavy lifting (file system operations, process invocation, rendering pipelines) must run asynchronously off the Main thread using modern Swift Concurrency (`async/await`, `Task`, `AsyncSequence`).

#### 3. Deep-Dive: Processing Engines by Format

##### A. Image Optimization (Adapted from ImageOptim Concepts)
- **Engine:** Bundled open-source CLI tools embedded directly in the main app bundle (`Contents/Resources/`).
- **Target Tools:** `pngquant` / `OxiPNG` (for PNGs), `MozJPEG` (for JPEGs), and `Gifsicle` (for GIFs).
- **Execution:** Managed via Swift’s native `Process` (`NSTask`) API. The Swift wrapper will pass optimized flags to the binaries and handle stdout/stderr tracking.

##### B. Video Optimization (FFmpeg Integration)
- **Engine:** A bundled compiled open-source `ffmpeg` CLI binary embedded inside the app bundle (`Contents/Resources/ffmpeg`).
- **Execution:** Invoked asynchronously via native Swift `Process()`. No third-party Objective-C or Swift wrappers should be used.
- **Compression Strategy:** Transcode incoming video formats (`.mp4`, `.mov`, `.mkv`) using the H.264 or HEVC (H.265) video codec coupled with a Constant Rate Factor (CRF) target for optimal quality-to-size balancing. Audio should be cleanly passed or transcoded to standard AAC.
- **Progress Tracking:** Parse the realtime `stderr` output stream of the FFmpeg execution thread to extract time/duration tokens, matching them against the file's metadata to calculate an active progress percentage.

##### C. PDF Optimization (Native macOS Quartz Core)
- **Engine:** Pure native implementation using Apple's built-in `QuartzCore`, `CoreGraphics`, and `PDFKit` frameworks. No external CLI binaries or heavy dependencies allowed.
- **Execution:** Load the targeted document using `CGPDFDocument` or `PDFDocument`.
- **Compression Strategy:** Export a new document by drawing pages into a configured `CGPDFContext` that enforces lossy JPEG compression on embedded bitmap elements and downsamples high-DPI imagery to a standard screen-friendly 150 DPI resolution constraint.

#### 4. UX / UI Requirements (SwiftUI)
- **Interface:** A sleek, minimal dropdown panel anchoring natively from the macOS menu bar icon.
- **Interaction:** A highly visible "Drop Files Here" landing zone supporting drag-and-drop operations directly over the menu bar icon or into the open view panel.
- **State Management:** - Provide active visual feedback (progress bars, processing states, or indeterminate spinners) while files are inside execution queues.
  - Maintain a clean, scrollable history list showing recently optimized items alongside their specific space-saving stats (e.g., "5.2 MB → 1.8 MB (-65%)").
- **Tip Jar Integration:** A beautifully styled button at the base of the UI panel labeled "Support the Developer ☕" or "Buy Me a Coffee" that triggers an external browser redirect using `NSWorkspace.shared.open()`.

#### 5. Code Generation Guidelines
- Design modular service classes (`ImageOptimizationService`, `VideoOptimizationService`, `PDFOptimizationService`) that all conform to a unified `MediaOptimizerProtocol`.
- The protocol should yield a standardized asynchronous stream or state updater providing status changes (`idle`, `processing(percentage)`, `completed(metrics)`, `failed(error)`).
- Ensure safe pathing: implement proper handling of sandboxed temporary directories for execution files to ensure user data is never lost or corrupted during an optimization crash.
