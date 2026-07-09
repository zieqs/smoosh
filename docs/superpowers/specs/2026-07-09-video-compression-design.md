# Video Compression — Design Spec

## Overview

Add video file optimization to Smoosh using an FFmpeg-first strategy (`ffmpeg` CLI via `ProcessRunner`) with a native `AVAssetExportSession` fallback. Follows the same architecture pattern as `PDFOptimizationService` and `ImageOptimizationService`.

## Supported Formats

| Direction | Format | Codec | Container |
|-----------|--------|-------|-----------|
| Input | MP4, MOV | Any macOS-playable | `.mp4`, `.mov` |
| Output | MP4 | H.264 (AVC) | `.mp4` |

## Tools

- **Primary:** `ffmpeg` — CLI tool providing consistent, absolute-quality H.264 encoding via CRF. Bundled in `resources/release-binaries/` for Release, `PATH` for Debug.
- **Fallback:** `AVAssetExportSession` — built-in macOS 14+ video export. Used when ffmpeg fails or produces output larger than input.

## Architecture

```
OptimizationCoordinator.shared.optimize(fileAt:, appState:)
  ├─ UTType.image  → ImageOptimizationService
  ├─ UTType.pdf    → PDFOptimizationService
  └─ UTType.movie  → VideoOptimizationService
       ├─ Primary: ffmpeg (libx264 CRF)  → success → compare → done
       ├─ Fallback: AVAssetExportSession → success → compare → done
       └─ Neither smaller → keep original, 0% savings
```

### `VideoOptimizationService` (singleton)

- Mirrors `PDFOptimizationService` — not a `MediaOptimizerProtocol` conformer
- Runs optimization in an async `Task`
- Creates temp output in `FileManager.default.temporaryDirectory`
- Updates `AppState` via `replaceItem` on each state change

#### FFmpeg path (primary)

1. Run `ffmpeg` via `ProcessRunner.run` with arguments:
   ```
   ffmpeg -y -i input.mp4 <videoArgs> -c:a copy -map 0:v -map 0:a? \
          -movflags +faststart -progress pipe:2 -nostats -hide_banner output.mp4
   ```
   - Preset `Fast` on Apple Silicon uses `h264_videotoolbox -q:v 50` (hardware Media Engine)
   - Preset `Fast` on Intel uses `libx264 -crf 28 -preset veryfast`
   - Presets `Low`/`Medium`/`High` use `libx264 -preset slower` with CRF 25/22/19
2. `-preset slower` used for better compression efficiency at same quality
3. `-c:a copy` preserves original audio unchanged
4. `-progress pipe:2` enables real-time progress parsing from stderr
5. No scaling — resolution preserved
6. If exit code is zero and output file exists, compare sizes
7. If smaller, move to `filename_smoosh.mp4`; otherwise try native fallback

#### Native fallback (`AVAssetExportSession`)

Triggered when:
- FFmpeg binary not found (not installed)
- FFmpeg exits non-zero
- FFmpeg output is larger than or equal to input

1. Load `AVURLAsset` from input URL, check readability
2. Create `AVAssetExportSession(preset:)` — preset mapped from quality slider:
   - 0.00–0.33 → `AVAssetExportPresetLowQuality`
   - 0.34–0.66 → `AVAssetExportPresetMediumQuality`
   - 0.67–1.00 → `AVAssetExportPresetHighestQuality`
3. Set `outputFileType = .mp4`, `outputURL` to temp file
4. Poll `session.progress` on timer for `.processing(progress:)` updates
5. Await completion via `withCheckedContinuation`
6. If output file exists and is smaller, move to `_smoosh.mp4`; otherwise keep original

### Output naming

Always `filename_smoosh.mp4`. If neither path produces a smaller file, keep the original and report 0% savings.

### Audio handling

Audio is always copied as-is (ffmpeg: `-c:a copy`; native: included tracks). No re-encoding.

### Resolution

Original resolution is preserved. No scaling.

## Quality Mapping

| Preset | FFmpeg args | AVAssetExport preset |
|--------|-------------|----------------------|
| Fast (Apple Silicon) | `h264_videotoolbox -q:v 50` | LowQuality |
| Fast (Intel) | `libx264 -crf 28 -preset veryfast` | LowQuality |
| Low | `libx264 -crf 25 -preset slower` | LowQuality |
| Medium (default) | `libx264 -crf 22 -preset slower` | MediumQuality |
| High | `libx264 -crf 19 -preset slower` | HighestQuality |

## Preferences

### Model (`Preferences.swift`)

```swift
enum VideoQuality: String, Codable, CaseIterable {
    case fast
    case low
    case medium
    case high
}

var videoQuality: VideoQuality
    default .medium
```

### View (`PreferencesView.swift`)

```
Video Quality
[Fast | Low | Medium | High]
```

Window height: 240.

## File Changes

### New Files

- `smoosh/Services/VideoOptimizationService.swift` — singleton service with ffmpeg → native fallback

### Modified Files

- `smoosh/Services/OptimizationCoordinator.swift` — add `UTType.movie` branch
- `smoosh/Models/Preferences.swift` — add `videoQuality: VideoQuality` enum (fast/low/medium/high)
- `smoosh/Models/OptimizationItem.swift` — add `var isVideo: Bool`
- `smoosh/Views/PreferencesView.swift` — add video quality segmented picker
- `smoosh/Views/DropZoneView.swift` — add `.movie`, `.mpeg4Movie`, `.quickTimeMovie` to `supportedTypes`; update label
- `smoosh.xcodeproj/project.pbxproj` — add ffmpeg to Copy Release Dylibs build phase inputPaths
- `README.md` — update engines table to reflect ffmpeg-primary architecture

### Resources

- `resources/release-binaries/ffmpeg` — minimal static build (H.264 encode, MP4/MOV support, AAC passthrough). Optional for Debug (uses Homebrew via PATH).

## Data Flow

1. User drops `.mp4` or `.mov` file
2. `DropZoneView` calls `OptimizationCoordinator.shared.optimize(fileAt:, appState:)`
3. Coordinator detects `UTType.movie` and dispatches to `VideoOptimizationService.shared.optimize(...)`
4. Service creates temp output directory, adds pending `OptimizationItem` to `AppState`
5. **FFmpeg path:** Runs `ffmpeg` via `ProcessRunner`, writes to temp
   - On success and smaller: move to `filename_smoosh.mp4`, complete
   - On failure or larger: discard temp, proceed to native fallback
6. **Native fallback:** Runs `AVAssetExportSession`, exports to temp
   - On success and smaller: move to `filename_smoosh.mp4`, complete
   - On failure or larger: discard temp, keep original, 0% savings
7. If neither path produces a smaller file, keep original and report 0% savings

## Progress Reporting

- **FFmpeg:** Probe input duration via `AVURLAsset.load(.duration)` before encoding; parse `out_time_ms=` from ffmpeg `-progress pipe:2` output; emit `.processing(progress:)` as 0.0–1.0.
- **Native fallback:** Poll `exportSession.progress` every 0.25s, emit `.processing(progress:)` with value 0.0–1.0

## Error Handling

| Scenario | Behavior |
|----------|----------|
| FFmpeg binary not found | Fallback to AVAssetExportSession |
| FFmpeg exits non-zero | Fallback to AVAssetExportSession |
| FFmpeg output larger than input | Fallback to AVAssetExportSession |
| Native export fails | `.failed("Could not process video")` |
| Native output larger | Keep original, 0% savings |
| Unsupported codec/format | Both fail → `.failed` |
| Temp file I/O error | `.failed` with IO error |

## Binary Bundling

- **Debug:** `BinaryLocator.url(for: "ffmpeg")` finds it in PATH (Homebrew via `which`)
- **Release:** Minimal static `ffmpeg` binary in `resources/release-binaries/ffmpeg`; added to Xcode build phase inputPaths. No additional dylibs needed if built statically.

## UI Changes

- Drop zone label: "Supports images, PDFs, and video"
- Video items show indeterminate spinner during FFmpeg processing; percentage progress during native fallback
- History badges and retry button work identically to images/PDFs
- Filename pattern: `filename_smoosh.mp4` placed next to the original

## Out of Scope for v1

- HEVC/H.265 encoding
- Resolution downscaling
- Audio re-encoding options
- Batch progress aggregation
- Video metadata preservation (rotation, chapters, subtitles)
- WebM, AVI, MKV support
- Frame-rate modification
