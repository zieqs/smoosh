# Video Compression Implementation Plan

**Goal:** Add video optimization to Smoosh using AVAssetExportSession (native) with FFmpeg fallback.

**Architecture:** VideoOptimizationService singleton routes through native AVAssetExportSession first, then falls back to bundled ffmpeg. Quality controlled by a single preferences slider.

**Tech Stack:** Swift, AVFoundation, Swift Concurrency, ffmpeg

---

### Task 1: Add `videoQuality` to Preferences

**Files:**
- Modify: `smoosh/Models/Preferences.swift`

- [ ] Add `var videoQuality: Double` with UserDefaults persistence, default `0.7`

### Task 2: Add `isVideo` to OptimizationItem

**Files:**
- Modify: `smoosh/Models/OptimizationItem.swift`

- [ ] Add `var isVideo: Bool` computed property using UTType

### Task 3: Create VideoOptimizationService

**Files:**
- Create: `smoosh/Services/VideoOptimizationService.swift`

- [ ] Implement singleton service with native AVAssetExportSession path and ffmpeg fallback
- [ ] Map quality slider to AVAssetExport presets and ffmpeg CRF
- [ ] Progress reporting for both paths

### Task 4: Update OptimizationCoordinator

**Files:**
- Modify: `smoosh/Services/OptimizationCoordinator.swift`

- [ ] Add `utType.conforms(to: .movie)` branch dispatching to VideoOptimizationService

### Task 5: Update DropZoneView

**Files:**
- Modify: `smoosh/Views/DropZoneView.swift`

- [ ] Add `.movie`, `.mpeg4Movie`, `.quickTimeMovie` to supportedTypes
- [ ] Update label to "Supports images, PDFs, and video"

### Task 6: Update PreferencesView

**Files:**
- Modify: `smoosh/Views/PreferencesView.swift`

- [ ] Add video quality slider section below PDF section

### Task 7: Bundle ffmpeg and update Xcode project

**Files:**
- Add: `resources/release-binaries/ffmpeg`
- Modify: `smoosh.xcodeproj/project.pbxproj`

- [ ] Copy ffmpeg binary to release-binaries
- [ ] Add ffmpeg to Copy Release Dylibs inputPaths

### Task 8: Build and verify

- [ ] Run `xcodebuild` and fix any build errors
