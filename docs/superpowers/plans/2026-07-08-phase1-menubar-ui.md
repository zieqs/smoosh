# Phase 1: Menu Bar App & UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the default WindowGroup app into a macOS MenuBarExtra app with a functional drag-and-drop UI shell — no optimization engines yet.

**Architecture:** The app entry point uses SwiftUI's `MenuBarExtra` scene. A shared `@Observable AppState` object drives the UI. `ContentView` composes three subviews: a `DropZoneView` for file input, a `HistoryListView` for dropped items, and a `TipJarButton`.

**Tech Stack:** Swift, SwiftUI, macOS 14+, `MenuBarExtra`, `@Observable`, `UniformTypeIdentifiers`

## Global Constraints

- Target macOS 14+ (Sonoma or later)
- Bundle identifier: `com.zieqs.smoosh`
- Use `@Observable` macro for app state (macOS 14+)
- No third-party dependencies
- All views must be `struct` types
- Use `PBXFileSystemSynchronizedRootGroup` — creating files in `smoosh/` auto-includes them in Xcode
- No test target exists yet; skip unit tests for Phase 1

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `smoosh/smooshApp.swift` | Modify | `MenuBarExtra` entry point |
| `smoosh/ContentView.swift` | Modify | Compose all subviews |
| `smoosh/Models/AppState.swift` | Create | `@Observable` app state |
| `smoosh/Models/OptimizationItem.swift` | Create | History item data model |
| `smoosh/Views/DropZoneView.swift` | Create | Drag-and-drop file landing zone |
| `smoosh/Views/HistoryListView.swift` | Create | Scrollable history of dropped items |
| `smoosh/Views/TipJarButton.swift` | Create | "Support the Developer" button |

---

### Task 1: App State Models

**Files:**
- Create: `smoosh/Models/OptimizationItem.swift`
- Create: `smoosh/Models/AppState.swift`
- Modify: (none yet)

**Interfaces:**
- Consumes: Foundation
- Produces: `OptimizationItem` struct, `AppState` `@Observable` class

- [ ] **Step 1: Create OptimizationItem data model**

Write `smoosh/Models/OptimizationItem.swift`:

```swift
import Foundation

struct OptimizationItem: Identifiable {
    let id = UUID()
    let fileName: String
    let fileSize: Int64
    let optimizedSize: Int64?
    let status: Status

    enum Status {
        case pending
        case processing
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
        return String(format: "-%.0f%%", pct)
    }
}
```

- [ ] **Step 2: Create AppState observable class**

Write `smoosh/Models/AppState.swift`:

```swift
import Foundation

@Observable
final class AppState {
    var history: [OptimizationItem] = []

    func addItem(_ item: OptimizationItem) {
        history.insert(item, at: 0)
    }

    func removeItems(at offsets: IndexSet) {
        history.remove(atOffsets: offsets)
    }

    func clearHistory() {
        history.removeAll()
    }
}
```

- [ ] **Step 3: Verify Xcode picks up the new files**

Run: `ls smoosh/Models/` — should show both `.swift` files.
Open Xcode: `xed smoosh.xcodeproj` and confirm `Models` group appears in the project navigator.

---

### Task 2: Convert App Entry Point to MenuBarExtra

**Files:**
- Modify: `smoosh/smooshApp.swift`

**Interfaces:**
- Consumes: `AppState`
- Produces: `MenuBarExtra` scene with `ContentView`

- [ ] **Step 1: Rewrite smooshApp.swift**

Replace the entire file with:

```swift
import SwiftUI

@main
struct smooshApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environment(appState)
                .frame(width: 300)
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
        }
    }
}
```

- [ ] **Step 2: Build and run to verify**

Run: `xcodebuild -project smoosh.xcodeproj -scheme smoosh -destination 'platform=macOS' build`
Expected: Build succeeds. App launches as a menu bar item (arrow icon in menu bar). Clicking it shows an empty popover with default ContentView text.

---

### Task 3: Drop Zone View

**Files:**
- Create: `smoosh/Views/DropZoneView.swift`

**Interfaces:**
- Consumes: `AppState` from environment, `OptimizationItem`, `.fileURL` from `UniformTypeIdentifiers`
- Produces: `DropZoneView` SwiftUI view

- [ ] **Step 1: Create DropZoneView**

Write `smoosh/Views/DropZoneView.swift`:

```swift
import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @Environment(AppState.self) private var appState
    @State private var isDragging = false

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(style: StrokeStyle(lineWidth: 2, dash: [6]))
            .foregroundStyle(isDragging ? Color.accentColor : Color.secondary)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc")
                        .font(.largeTitle)
                        .foregroundStyle(isDragging ? Color.accentColor : Color.secondary)
                    Text("Drop files here")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Images, videos, and PDFs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 130)
            .padding()
            .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
                handleDrop(providers)
                return true
            }
            .animation(.easeInOut(duration: 0.2), value: isDragging)
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil)
                else { return }

                let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey])
                let size = Int64(resourceValues?.fileSize ?? 0)

                Task { @MainActor in
                    appState.addItem(OptimizationItem(
                        fileName: url.lastPathComponent,
                        fileSize: size,
                        optimizedSize: nil,
                        status: .pending
                    ))
                }
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project smoosh.xcodeproj -scheme smoosh -destination 'platform=macOS' build`
Expected: Build succeeds.

---

### Task 4: History List View

**Files:**
- Create: `smoosh/Views/HistoryListView.swift`

**Interfaces:**
- Consumes: `AppState` from environment, `OptimizationItem`
- Produces: `HistoryListView` SwiftUI view

- [ ] **Step 1: Create HistoryListView**

Write `smoosh/Views/HistoryListView.swift`:

```swift
import SwiftUI

struct HistoryListView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.history.isEmpty {
            emptyState
        } else {
            List {
                ForEach(appState.history) { item in
                    HistoryRow(item: item)
                }
                .onDelete { offsets in
                    appState.removeItems(at: offsets)
                }
            }
            .listStyle(.plain)
            .frame(minHeight: 100)
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

    private var statusBadge: some View {
        switch item.status {
        case .pending:
            return Badge(text: "Pending", color: .orange)
        case .processing:
            return Badge(text: "Processing...", color: .blue)
        case .completed:
            return Badge(text: item.formattedSavings ?? "Done", color: .green)
        case .failed:
            return Badge(text: "Failed", color: .red)
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

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project smoosh.xcodeproj -scheme smoosh -destination 'platform=macOS' build`
Expected: Build succeeds.

---

### Task 5: Tip Jar Button

**Files:**
- Create: `smoosh/Views/TipJarButton.swift`

**Interfaces:**
- Produces: `TipJarButton` SwiftUI view

- [ ] **Step 1: Create TipJarButton**

Write `smoosh/Views/TipJarButton.swift`:

```swift
import SwiftUI

struct TipJarButton: View {
    var body: some View {
        Button {
            if let url = URL(string: "https://ko-fi.com/zieqs") {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Label("Support the Developer ☕", systemImage: "cup.and.saucer.fill")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project smoosh.xcodeproj -scheme smoosh -destination 'platform=macOS' build`
Expected: Build succeeds.

---

### Task 6: Compose ContentView

**Files:**
- Modify: `smoosh/ContentView.swift`

**Interfaces:**
- Consumes: `DropZoneView`, `HistoryListView`, `TipJarButton`
- Produces: Composed `ContentView`

- [ ] **Step 1: Rewrite ContentView**

Replace the entire file with:

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 0) {
            DropZoneView()

            Divider()
                .padding(.horizontal)

            HistoryListView()

            Divider()
                .padding(.horizontal)

            TipJarButton()
        }
    }
}
```

- [ ] **Step 2: Full build and run**

Run: `xcodebuild -project smoosh.xcodeproj -scheme smoosh -destination 'platform=macOS' build`
Expected: Build succeeds.

- [ ] **Step 3: Manual smoke test**

Open the app: `open build/Release/smoosh.app` (or run from Xcode).
Expected: Menu bar icon appears. Clicking it shows the drop zone, "No files yet" message, and the tip jar button. Dragging a file onto the drop zone adds it to the history list.

---

### Task 7: Add Clear History Button

**Files:**
- Modify: `smoosh/HistoryListView.swift`

- [ ] **Step 1: Add clear button to HistoryListView**

After the empty state check, add a header with clear button for non-empty history:

Replace `HistoryListView` body to:

```swift
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
                    HistoryRow(item: item)
                }
                .onDelete { offsets in
                    appState.removeItems(at: offsets)
                }
            }
            .listStyle(.plain)
            .frame(minHeight: 100)
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project smoosh.xcodeproj -scheme smoosh -destination 'platform=macOS' build`
Expected: Build succeeds. History section now shows "History" header with "Clear" button.

---

### Task 8: Polish — Fixed Popover Width & Menu Bar Icon

**Files:**
- Modify: `smoosh/smooshApp.swift`
- Modify: `smoosh/ContentView.swift`

- [ ] **Step 1: Update smooshApp.swift to use a more descriptive menu bar icon**

Change `Image(systemName: "arrow.up.arrow.down.circle")` to:

```swift
Image(systemName: "arrow.up.arrow.down.circle.fill")
```

Add menu bar extra configuration if needed (not strictly required, but ensures consistent sizing).

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project smoosh.xcodeproj -scheme smoosh -destination 'platform=macOS' build`
Expected: Build succeeds.
