# PDF Optimization — Design Spec

## Overview

Add PDF file optimization to Smoosh by bundling the `qpdf` CLI tool and integrating it into the app architecture alongside the existing image pipeline.

## Tools

- **qpdf** (Apache 2.0) — structural PDF optimization via stream compression, object stream generation, and flate recompression
- No native macOS frameworks used for the optimization itself; Swift `Process` API launches `qpdf`
- Bundled for Release builds; found via `PATH` (typically Homebrew) for Debug builds

## Architecture

```
DropZoneView
  └─ OptimizationCoordinator.shared.optimize(fileAt:, appState:)
       ├─ UTType.image → ImageOptimizationService.shared.optimize(...)
       └─ UTType.pdf   → PDFOptimizationService.shared.optimize(...)
```

### New Files

- `smoosh/Services/OptimizationCoordinator.swift`  
  Singleton router. Receives a file URL, inspects `UTType`, dispatches to the appropriate service. Single point of entry for the UI layer. Future home for video routing.

- `smoosh/Services/PDFOptimizationService.swift`  
  Singleton service. Validates the file, runs `qpdf` via `ProcessRunner`, writes output to a temp directory, compares sizes, moves output to `filename_smoosh.pdf` if smaller, and updates `AppState` with the result.

### Modified Files

- `smoosh/Views/DropZoneView.swift`  
  Supported types: add `.pdf`. Folder enumeration: add `.pdf`. Dispatch via `OptimizationCoordinator`. Label text: "Supports images, PDFs".

- Xcode project  
  Copy Files Build Phase for `qpdf` binary.

- `resources/release-binaries/`  
  Pre-linked `qpdf` binary.

- `resources/release-dylibs/`  
  Dylibs required by `qpdf` (`libssl`, `libcrypto`).

## qpdf Invocation

Flags: `qpdf --object-streams=generate --compress-streams=y --recompress-flate input.pdf output.pdf`

This performs three optimizations:
1. **Object streams**: groups objects into compressed streams, reducing overhead
2. **Stream compression**: compresses all uncompressed streams with Flate
3. **Flate recompression**: re-encodes existing Flate streams with better compression

`qpdf` does not emit progress information, so the UI shows an indeterminate spinner during PDF optimization.

## Data Flow

1. User drops `.pdf` file
2. `DropZoneView` calls `OptimizationCoordinator.shared.optimize(fileAt:url, appState:appState)`
3. `OptimizationCoordinator` detects `UTType.pdf` and dispatches to `PDFOptimizationService.shared.optimize(...)`
4. Service adds a pending `OptimizationItem`, runs `qpdf` to a temp file
5. On success: compare sizes. If temp is smaller, move to `filename_smoosh.pdf`; otherwise discard and report 0% savings
6. On failure: discard temp, report error
7. Service updates the `OptimizationItem` in `AppState`

## Error Handling

| Scenario | Behavior |
|----------|----------|
| `qpdf` binary not found | `.failed("qpdf not found")` |
| `qpdf` exits non-zero | `.failed` with process error, stderr hidden (user-friendly message) |
| Output larger than input | Keep original, 0% savings |
| Encrypted/protected PDF | `qpdf` will fail; report "Protected PDF" |
| Temp file I/O error | `.failed` with IO error |

## Binary Bundling

- **Debug**: `BinaryLocator` finds `qpdf` in PATH (Homebrew). `ProcessRunner` already injects `/opt/homebrew/lib` for dylibs.
- **Release**: `qpdf` is pre-linked with `@rpath`, placed in `resources/release-binaries/`. Required dylibs in `resources/release-dylibs/`. Copy Files Build Phase copies both to `Contents/Resources/`.

## UI Changes

- Drop zone label updates to "Supports images, PDFs"
- PDF items show an indeterminate `ProgressView` spinner (no percentage possible)
- History badges and retry button work identically to images
- Filename pattern: `filename_smoosh.pdf` placed next to the original

## Future Considerations

- Video optimization will follow the same pattern: new `VideoOptimizationService`, routing added to `OptimizationCoordinator`
- If `qpdf` proves insufficient for image-heavy PDFs, a future pass could add CoreGraphics-based image re-encoding alongside `qpdf`
