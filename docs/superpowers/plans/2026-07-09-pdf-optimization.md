# PDF Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add PDF optimization support to Smoosh using bundled qpdf CLI.

**Architecture:** Create OptimizationCoordinator singleton that routes file drops to either ImageOptimizationService (existing) or PDFOptimizationService (new) based on UTType. DropZoneView calls the coordinator instead of ImageOptimizationService directly.

**Tech Stack:** Swift, ProcessRunner (existing), BinaryLocator (existing), qpdf CLI

## Global Constraints

- macOS 14+ deployment target
- No third-party Swift packages
- qpdf flags: `--object-streams=generate --compress-streams=y --recompress-flate`
- Output: `filename_smoosh.pdf` next to original
- If output is larger: keep original, report 0% savings
- Indeterminate spinner for PDF processing (no progress output from qpdf)
- Error messages: user-friendly, hide raw exit codes (same pattern as images)
- Debug: qpdf from PATH, DYLD_FALLBACK_LIBRARY_PATH for dylibs
- Release: pre-linked qpdf + dylibs bundled in Resources

---
### Task 1: OptimizationCoordinator

**Files:**
- Create: `smoosh/Services/OptimizationCoordinator.swift`

**Interfaces:**
- Consumes: `ImageOptimizationService.shared`, `PDFOptimizationService.shared`
- Produces: `OptimizationCoordinator.shared.optimize(fileAt: URL, appState: AppState)`

- [ ] **Step 1: Write OptimizationCoordinator**

```swift
import Foundation
import UniformTypeIdentifiers

final class OptimizationCoordinator {
    static let shared = OptimizationCoordinator()

    private init() {}

    func optimize(fileAt url: URL, appState: AppState) {
        guard let utType = UTType(filenameExtension: url.pathExtension) else {
            return
        }

        if utType.conforms(to: .pdf) {
            PDFOptimizationService.shared.optimize(fileAt: url, appState: appState)
        } else if utType.conforms(to: .image) {
            ImageOptimizationService.shared.optimize(fileAt: url, appState: appState)
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add smoosh/Services/OptimizationCoordinator.swift
git commit -m "feat: add OptimizationCoordinator for file-type routing"
```

---
### Task 2: PDFOptimizationService

**Files:**
- Create: `smoosh/Services/PDFOptimizationService.swift`

**Interfaces:**
- Consumes: `ProcessRunner.run(executableURL:arguments:)` (via BinaryLocator), `AppState` (addItem/replaceItem)
- Produces: `PDFOptimizationService.shared.optimize(fileAt: URL, appState: AppState)`

- [ ] **Step 1: Write PDFOptimizationService**

```swift
import Foundation
import UniformTypeIdentifiers

final class PDFOptimizationService {
    static let shared = PDFOptimizationService()

    private init() {}

    func optimize(fileAt url: URL, appState: AppState) {
        let item = OptimizationItem(
            id: UUID(), fileName: url.lastPathComponent,
            fileSize: (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64 ?? 0,
            optimizedSize: nil, sourceURL: url, status: .pending
        )

        let outputURL = url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + "_smoosh.pdf")

        Task { @MainActor in
            appState.addItem(item)

            guard let qpdf = BinaryLocator.url(for: "qpdf") else {
                appState.replaceItem(item.id, with: OptimizationItem(
                    id: item.id, fileName: url.lastPathComponent,
                    fileSize: item.fileSize, optimizedSize: nil,
                    sourceURL: url, status: .failed("qpdf not found")
                ))
                return
            }

            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            let tempOutput = tempDir.appendingPathComponent(outputURL.lastPathComponent)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            do {
                appState.replaceItem(item.id, with: OptimizationItem(
                    id: item.id, fileName: url.lastPathComponent,
                    fileSize: item.fileSize, optimizedSize: nil,
                    sourceURL: url, status: .processing(0)
                ))

                let result = try await ProcessRunner.run(
                    executableURL: qpdf,
                    arguments: [
                        "--object-streams=generate",
                        "--compress-streams=y",
                        "--recompress-flate",
                        url.path,
                        tempOutput.path
                    ]
                )

                if result.exitCode == 0 {
                    let optimizedSize = (try? FileManager.default.attributesOfItem(atPath: tempOutput.path))?[.size] as? Int64 ?? 0
                    let isSmaller = optimizedSize < item.fileSize

                    if isSmaller {
                        try? FileManager.default.moveItem(at: tempOutput, to: outputURL)
                    } else {
                        try? FileManager.default.removeItem(at: tempOutput)
                    }

                    appState.replaceItem(item.id, with: OptimizationItem(
                        id: item.id, fileName: url.lastPathComponent,
                        fileSize: item.fileSize,
                        optimizedSize: isSmaller ? optimizedSize : item.fileSize,
                        sourceURL: url, status: .completed
                    ))
                } else {
                    try? FileManager.default.removeItem(at: tempOutput)
                    appState.replaceItem(item.id, with: OptimizationItem(
                        id: item.id, fileName: url.lastPathComponent,
                        fileSize: item.fileSize, optimizedSize: nil,
                        sourceURL: url,
                        status: .failed(result.exitCode > 128 ? "Out of memory" : "Optimization failed")
                    ))
                }
            } catch {
                try? FileManager.default.removeItem(at: tempOutput)
                appState.replaceItem(item.id, with: OptimizationItem(
                    id: item.id, fileName: url.lastPathComponent,
                    fileSize: item.fileSize, optimizedSize: nil,
                    sourceURL: url, status: .failed(error.localizedDescription)
                ))
            }

            try? FileManager.default.removeItem(at: tempDir)
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add smoosh/Services/PDFOptimizationService.swift
git commit -m "feat: add PDFOptimizationService using qpdf"
```

---
### Task 3: Update DropZoneView

**Files:**
- Modify: `smoosh/Views/DropZoneView.swift`

**Interfaces:**
- Consumes: `OptimizationCoordinator.shared.optimize(fileAt:appState:)`
- Produces: Updated drop zone with .pdf support

- [ ] **Step 1: Update supported types, folder enumeration, and dispatch**

Replace `ImageOptimizationService.shared.optimize(fileAt:child, appState: appState)` with `OptimizationCoordinator.shared.optimize(fileAt: child, appState: appState)` in both single-file and folder-drop paths.

Add `.pdf` to `supportedTypes` array in `processURL`.

Update label text.

Changes in `DropZoneView.swift`:

```swift
// Line 21: update label
Text("Supports images, PDFs")

// Line 68: add .pdf to supported types
let supportedTypes: [UTType] = [.png, .jpeg, .gif, .pdf]

// Line 74: replace ImageOptimizationService shared call
OptimizationCoordinator.shared.optimize(fileAt: child, appState: appState)

// Line 77: replace ImageOptimizationService shared call
OptimizationCoordinator.shared.optimize(fileAt: url, appState: appState)
```

- [ ] **Step 2: Commit**

```bash
git add smoosh/Views/DropZoneView.swift
git commit -m "feat: add PDF support to DropZoneView via OptimizationCoordinator"
```

---
### Task 4: Bundle qpdf binary

**Files:**
- Modify: Xcode project (add Copy Files build phase rule)
- Add: `resources/release-binaries/qpdf`
- Add: required dylibs to `resources/release-dylibs/`

**Prerequisites:** qpdf must be installed via Homebrew (`brew install qpdf`)

**Context:** The Xcode project has two Copy Files build phases — one for copying binaries and one for copying dylibs. We add qpdf to the binaries phase and its dylibs to the dylibs phase.

- [ ] **Step 1: Install qpdf via Homebrew**

```bash
brew install qpdf
```

- [ ] **Step 2: Locate qpdf binary and its dylibs**

```bash
which qpdf
otool -L $(which qpdf)
```

- [ ] **Step 3: Pre-link qpdf with @rpath and add to release-binaries**

Use `install_name_tool -change` for each dylib path, same pattern as existing image binaries.

- [ ] **Step 4: Add qpdf to Xcode Copy Files build phase (Release)**

Open the project in Xcode and add qpdf to the binary Copy Files phase, and its dylibs to the dylibs Copy Files phase.

- [ ] **Step 5: Commit**

```bash
git add resources/release-binaries/qpdf
git add resources/release-dylibs/<new-dylibs>
git add smoosh.xcodeproj/project.pbxproj
git commit -m "feat: bundle qpdf binary for PDF optimization"
```

---
### Task 5: Verify build

- [ ] **Step 1: Build and run**

```bash
xcodebuild -project smoosh.xcodeproj -scheme smoosh -configuration Debug
```

- [ ] **Step 2: Verify no build errors**

Check the build output for errors.

---
## Self-Review Checklist

1. **Spec coverage:** Spec requires OptimizationCoordinator ✓ (Task 1), PDFOptimizationService ✓ (Task 2), DropZoneView updates ✓ (Task 3), binary bundling ✓ (Task 4), error handling ✓ (Task 2), indeterminate spinner ✓ (Task 2 passes progress 0).
2. **Placeholders:** None.
3. **Type consistency:** `OptimizationCoordinator.shared.optimize(fileAt:appState:)` matches the usage in DropZoneView and the definition in Task 1. `PDFOptimizationService.shared.optimize(fileAt:appState:)` matches the call from OptimizationCoordinator and the definition in Task 2.
