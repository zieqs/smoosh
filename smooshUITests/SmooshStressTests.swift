import XCTest
import Foundation

final class SmooshStressTests: XCTestCase, @unchecked Sendable {

    private var app: XCUIApplication!
    private let baseFolder = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop/smoosh-stress")
    private let resultsFolder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("smoosh-results")
    private var currentTestMetrics = StressTestMetrics(testName: "", startTime: Date())

    // MARK: - Lifecycle

    override func setUp() async throws {
        continueAfterFailure = false
        try FileManager.default.createDirectory(at: resultsFolder, withIntermediateDirectories: true)
        await MainActor.run { [self] in
            app = XCUIApplication()
            app.terminate()
            cleanSmooshOutputs(in: baseFolder)
        }
    }

    override func tearDown() async throws {
        currentTestMetrics.endTime = Date()
        writeMetrics(currentTestMetrics)
        await MainActor.run { [self] in
            app?.terminate()
        }
    }

    // MARK: - Test Cases

    @MainActor
    func test01SmokeDragAndDrop() throws {
        let sourceFile = baseFolder.appendingPathComponent("01-valid-base/png-1k.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceFile.path), "Source fixture missing")

        app.launch()
        openPanel()

        let dropZone = app.descendants(matching: .any).matching(identifier: "dropZone").element
        XCTAssertTrue(dropZone.waitForExistence(timeout: 5))

        let dropped = simulateFileDrop(url: sourceFile, onto: dropZone)
        XCTAssertTrue(dropped, "Drag-and-drop simulation failed")

        let expectation = XCTestExpectation(description: "Wait for smoke test completion")
        waitForAllItemsToComplete(timeout: 60) { completed, failed in
            XCTAssertGreaterThan(completed, 0, "No items completed")
            XCTAssertEqual(failed, 0, "Smoke test had failures")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 70)
    }

    @MainActor
    func test02ValidBaseFiles() throws {
        let folder = baseFolder.appendingPathComponent("01-valid-base")
        currentTestMetrics = StressTestMetrics(testName: "valid-base", startTime: Date())
        runStressTest(folder: folder, timeout: 300)
    }

    @MainActor
    func test03FormatEdgeCases() throws {
        let folder = baseFolder.appendingPathComponent("02-format-edge")
        currentTestMetrics = StressTestMetrics(testName: "format-edge", startTime: Date())
        runStressTest(folder: folder, timeout: 120)
    }

    @MainActor
    func test04LargeFiles() throws {
        let folder = baseFolder.appendingPathComponent("03-large-files")
        currentTestMetrics = StressTestMetrics(testName: "large-files", startTime: Date())
        runStressTest(folder: folder, timeout: 600)
    }

    @MainActor
    func test05MalformedInputs() throws {
        let folder = baseFolder.appendingPathComponent("04-malformed")
        currentTestMetrics = StressTestMetrics(testName: "malformed-inputs", startTime: Date())
        runStressTest(folder: folder, timeout: 120)
    }

    @MainActor
    func test06BatchVolume50() throws {
        let folder = copyBatchSample(count: 50)
        currentTestMetrics = StressTestMetrics(testName: "batch-volume-50", startTime: Date())
        runStressTest(folder: folder, timeout: 300)
        try? FileManager.default.removeItem(at: folder)
    }

    @MainActor
    func test07BatchVolume150() throws {
        let folder = baseFolder.appendingPathComponent("05-batch-volume")
        currentTestMetrics = StressTestMetrics(testName: "batch-volume-150", startTime: Date())
        runStressTest(folder: folder, timeout: 600)
    }

    @MainActor
    func test08ConcurrencyStress() throws {
        let folder = baseFolder.appendingPathComponent("01-valid-base")
        let secondFolder = baseFolder.appendingPathComponent("02-format-edge")
        let combined = createCombinedFolder(name: "concurrency-combined", sources: [folder, secondFolder])
        currentTestMetrics = StressTestMetrics(testName: "concurrency", startTime: Date())
        runStressTest(folder: combined, timeout: 300)
        try? FileManager.default.removeItem(at: combined)
    }

    @MainActor
    func test09PresetSweep() throws {
        let video = baseFolder.appendingPathComponent("01-valid-base/mp4-1080p-60s.mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: video.path))

        var presetResults: [String: Int64] = [:]
        for preset in ["fast", "low", "medium", "high"] {
            cleanSmooshOutputs(in: video.deletingLastPathComponent())
            setVideoPreset(preset)

            currentTestMetrics = StressTestMetrics(testName: "preset-sweep-\(preset)", startTime: Date())
            app.launchArguments = ["--smoosh-stress-test", video.path]
            app.launch()
            waitForAllItemsToComplete(timeout: 300)

            let outputURL = video.deletingLastPathComponent()
                .appendingPathComponent(video.deletingPathExtension().lastPathComponent + "_smoosh.mp4")
            let size = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64) ?? 0
            presetResults[preset] = size
            app.terminate()
        }

        XCTAssertGreaterThan(presetResults["fast"] ?? 0, 0)
        XCTAssertGreaterThan(presetResults["low"] ?? 0, 0)
        XCTAssertGreaterThan(presetResults["medium"] ?? 0, 0)
        XCTAssertGreaterThan(presetResults["high"] ?? 0, 0)
    }

    @MainActor
    func test10UIStress() throws {
        app.launch()
        openPanel()

        for _ in 0..<10 {
            openPanel()
            sleep(1)
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
            sleep(1)
        }

        let prefs = app.descendants(matching: .any).matching(identifier: "preferencesButton").element
        if prefs.waitForExistence(timeout: 5) {
            prefs.click()
        }
    }

    // MARK: - Helpers

    @MainActor
    private func runStressTest(folder: URL, timeout: TimeInterval) {
        let originalSizes = collectFileSizes(in: folder)
        currentTestMetrics.fileCount = originalSizes.count
        currentTestMetrics.originalTotalBytes = originalSizes.values.reduce(0, +)

        app.launchArguments = ["--smoosh-stress-test", folder.path]
        app.launch()

        waitForAllItemsToComplete(timeout: timeout)

        let optimizedSizes = collectSmooshOutputs(in: folder)
        currentTestMetrics.optimizedTotalBytes = optimizedSizes.values.reduce(0, +)
        currentTestMetrics.successCount = optimizedSizes.count
        currentTestMetrics.failedCount = currentTestMetrics.fileCount - currentTestMetrics.successCount

        for (path, original) in originalSizes {
            let optimized = optimizedSizes[path] ?? 0
            let status: String = optimized > 0 ? "success" : "failed"
            currentTestMetrics.files.append(FileMetric(
                path: path,
                originalBytes: original,
                optimizedBytes: optimized,
                status: status
            ))
        }
    }

    @MainActor
    private func waitForAllItemsToComplete(timeout: TimeInterval, completion: ((Int, Int) -> Void)? = nil) {
        let deadline = Date().addingTimeInterval(timeout)
        var lastChange = Date()
        var lastCount = 0

        while Date() < deadline {
            let rows = app.descendants(matching: .any).matching(identifier: "historyRow-").allElementsBoundByIndex
            let total = rows.count
            let completed = rows.filter { $0.label.contains("Completed") || $0.label.contains("Failed") }.count

            if total > 0 && completed == total {
                completion?(rows.filter { $0.label.contains("Completed") }.count,
                            rows.filter { $0.label.contains("Failed") }.count)
                return
            }

            if total != lastCount {
                lastCount = total
                lastChange = Date()
            } else if Date().timeIntervalSince(lastChange) > 30 && total > 0 {
                completion?(rows.filter { $0.label.contains("Completed") }.count,
                            rows.filter { $0.label.contains("Failed") }.count)
                return
            }

            Thread.sleep(forTimeInterval: 1)
        }

        let rows = app.descendants(matching: .any).matching(identifier: "historyRow-").allElementsBoundByIndex
        completion?(rows.filter { $0.label.contains("Completed") }.count,
                    rows.filter { $0.label.contains("Failed") }.count)
    }

    @MainActor
    private func openPanel() {
        let statusItem = app.menuBars.statusItems["Smoosh"]
        if statusItem.waitForExistence(timeout: 5) {
            statusItem.click()
        }
        let dropZone = app.descendants(matching: .any).matching(identifier: "dropZone").element
        _ = dropZone.waitForExistence(timeout: 5)
    }

    @MainActor
    private func simulateFileDrop(url: URL, onto element: XCUIElement) -> Bool {
        let script = """
        tell application "System Events"
            tell process "smoosh"
                set frontmost to true
            end tell
        end tell
        """
        var errorInfo: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else { return false }
        appleScript.executeAndReturnError(&errorInfo)

        let pasteboard = NSPasteboard(name: .drag)
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])

        let coordinate = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let startCoordinate = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -0.2))
        startCoordinate.press(forDuration: 0.2, thenDragTo: coordinate)
        return true
    }

    private func setVideoPreset(_ preset: String) {
        let defaults = UserDefaults(suiteName: "com.zieqs.smoosh")
        defaults?.set(preset, forKey: "videoQuality")
        defaults?.synchronize()
    }

    private func collectFileSizes(in folder: URL) -> [String: Int64] {
        var sizes: [String: Int64] = [:]
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
        while let url = enumerator?.nextObject() as? URL {
            guard !url.hasDirectoryPath else { continue }
            guard !url.lastPathComponent.contains("_smoosh") else { continue }
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            sizes[url.path] = size
        }
        return sizes
    }

    private func collectSmooshOutputs(in folder: URL) -> [String: Int64] {
        // First, index all original files by their base name (without extension)
        var baseNameToPath: [String: String] = [:]
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
        while let url = enumerator?.nextObject() as? URL {
            guard !url.hasDirectoryPath else { continue }
            guard !url.lastPathComponent.contains("_smoosh") else { continue }
            baseNameToPath[url.deletingPathExtension().lastPathComponent] = url.path
        }

        // Then match _smoosh outputs to original files by base name
        var sizes: [String: Int64] = [:]
        let outputEnum = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
        while let url = outputEnum?.nextObject() as? URL {
            guard url.lastPathComponent.contains("_smoosh") else { continue }
            // Strip the _smoosh suffix and extension to get the base name
            let nameWithSmoosh = url.deletingPathExtension().lastPathComponent
            guard let range = nameWithSmoosh.range(of: "_smoosh") else { continue }
            let baseName = String(nameWithSmoosh[..<range.lowerBound])
            guard let originalPath = baseNameToPath[baseName] else { continue }
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            sizes[originalPath] = size
        }
        return sizes
    }

    private func cleanSmooshOutputs(in folder: URL) {
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent.contains("_smoosh") {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func copyBatchSample(count: Int) -> URL {
        let source = baseFolder.appendingPathComponent("05-batch-volume")
        let dest = URL(fileURLWithPath: "/tmp/smoosh-stress-work/batch-\(count)")
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)) ?? []
        let selected = Array(files.prefix(count))
        for file in selected {
            try? FileManager.default.copyItem(at: file, to: dest.appendingPathComponent(file.lastPathComponent))
        }
        return dest
    }

    private func createCombinedFolder(name: String, sources: [URL]) -> URL {
        let dest = URL(fileURLWithPath: "/tmp/smoosh-stress-work/\(name)")
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        var idx = 0
        for source in sources {
            let files = (try? FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)) ?? []
            for file in files where !file.hasDirectoryPath {
                idx += 1
                let ext = file.pathExtension
                let newName = "combined-\(idx).\(ext)"
                try? FileManager.default.copyItem(at: file, to: dest.appendingPathComponent(newName))
            }
        }
        return dest
    }

    private func writeMetrics(_ metrics: StressTestMetrics) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(metrics) else { return }
        let url = resultsFolder.appendingPathComponent("\(metrics.testName).json")
        try? data.write(to: url)
    }
}

// MARK: - Models

struct FileMetric: Codable {
    let path: String
    let originalBytes: Int64
    let optimizedBytes: Int64
    let status: String

    var savingsPercent: Double {
        guard originalBytes > 0, optimizedBytes > 0 else { return 0 }
        return (1.0 - Double(optimizedBytes) / Double(originalBytes)) * 100
    }
}

struct StressTestMetrics: Codable {
    let testName: String
    let startTime: Date
    var endTime: Date?
    var launchDuration: TimeInterval = 0
    var fileCount: Int = 0
    var successCount: Int = 0
    var failedCount: Int = 0
    var originalTotalBytes: Int64 = 0
    var optimizedTotalBytes: Int64 = 0
    var files: [FileMetric] = []

    var duration: TimeInterval {
        guard let endTime else { return 0 }
        return endTime.timeIntervalSince(startTime)
    }

    var totalSavingsPercent: Double {
        guard originalTotalBytes > 0, optimizedTotalBytes > 0 else { return 0 }
        return (1.0 - Double(optimizedTotalBytes) / Double(originalTotalBytes)) * 100
    }
}
