import Foundation
import UniformTypeIdentifiers
import AVFoundation

final class VideoOptimizationService {
    static let shared = VideoOptimizationService()

    private init() {}

    func optimize(fileAt url: URL, appState: AppState) {
        let item = OptimizationItem(
            id: UUID(), fileName: url.lastPathComponent,
            fileSize: (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64 ?? 0,
            optimizedSize: nil, sourceURL: url, status: .pending
        )

        let outputURL = url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + "_smoosh.mp4")

        Task { @MainActor in
            appState.addItem(item)

            appState.replaceItem(item.id, with: OptimizationItem(
                id: item.id, fileName: url.lastPathComponent,
                fileSize: item.fileSize, optimizedSize: nil,
                sourceURL: url, status: .processing(0)
            ))

            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            let tempOutput = tempDir.appendingPathComponent("output.mp4")
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let asset = AVURLAsset(url: url)
            let duration = try? await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration ?? .zero)

            if await runFFmpeg(input: url, output: tempOutput, duration: durationSeconds, item: item, appState: appState) {
                let optimizedSize = (try? FileManager.default.attributesOfItem(atPath: tempOutput.path))?[.size] as? Int64 ?? 0
                let isSmaller = optimizedSize < item.fileSize

                if isSmaller {
                    try? FileManager.default.moveItem(at: tempOutput, to: outputURL)
                } else {
                    try? FileManager.default.removeItem(at: tempOutput)
                }

                try? FileManager.default.removeItem(at: tempDir)

                appState.replaceItem(item.id, with: OptimizationItem(
                    id: item.id, fileName: url.lastPathComponent,
                    fileSize: item.fileSize,
                    optimizedSize: isSmaller ? optimizedSize : item.fileSize,
                    sourceURL: url, status: .completed
                ))
                return
            }

            try? FileManager.default.removeItem(at: tempOutput)

            if await tryNativeExport(input: url, output: tempOutput, item: item, appState: appState) {
                let optimizedSize = (try? FileManager.default.attributesOfItem(atPath: tempOutput.path))?[.size] as? Int64 ?? 0
                let isSmaller = optimizedSize < item.fileSize

                if isSmaller {
                    try? FileManager.default.moveItem(at: tempOutput, to: outputURL)
                } else {
                    try? FileManager.default.removeItem(at: tempOutput)
                }

                try? FileManager.default.removeItem(at: tempDir)

                appState.replaceItem(item.id, with: OptimizationItem(
                    id: item.id, fileName: url.lastPathComponent,
                    fileSize: item.fileSize,
                    optimizedSize: isSmaller ? optimizedSize : item.fileSize,
                    sourceURL: url, status: .completed
                ))
            } else {
                try? FileManager.default.removeItem(at: tempOutput)
                try? FileManager.default.removeItem(at: tempDir)

                appState.replaceItem(item.id, with: OptimizationItem(
                    id: item.id, fileName: url.lastPathComponent,
                    fileSize: item.fileSize, optimizedSize: nil,
                    sourceURL: url, status: .failed("Could not process video")
                ))
            }
        }
    }

    private func runFFmpeg(input url: URL, output tempOutput: URL, duration: Double, item: OptimizationItem, appState: AppState) async -> Bool {
        guard let ffmpeg = BinaryLocator.url(for: "ffmpeg") else {
            return false
        }

        appState.replaceItem(item.id, with: OptimizationItem(
            id: item.id, fileName: item.fileName,
            fileSize: item.fileSize, optimizedSize: nil,
            sourceURL: item.sourceURL, status: .processing(0)
        ))

        let progressLock = NSLock()
        var lastProgress: Double = 0

        let progressHandler: (Data) -> Void = { data in
            guard duration > 0, let text = String(data: data, encoding: .utf8) else { return }
            guard let match = text.range(of: "out_time_ms=") else { return }
            let start = match.upperBound
            guard let end = text[start...].range(of: "\n") else { return }
            let value = Double(text[start..<end.lowerBound]) ?? 0
            let progress = min(1.0, max(0.0, value / (duration * 1000.0)))

            progressLock.lock()
            defer { progressLock.unlock() }
            guard progress != lastProgress else { return }
            lastProgress = progress

            Task { @MainActor in
                appState.replaceItem(item.id, with: OptimizationItem(
                    id: item.id, fileName: item.fileName,
                    fileSize: item.fileSize, optimizedSize: nil,
                    sourceURL: item.sourceURL, status: .processing(progress)
                ))
            }
        }

        do {
            var arguments = ["-y", "-i", url.path]
            arguments += Preferences.shared.videoQuality.ffmpegVideoArgs
            arguments += [
                "-c:a", "copy",
                "-map", "0:v", "-map", "0:a?",
                "-movflags", "+faststart",
                "-progress", "pipe:2",
                "-nostats",
                "-hide_banner",
                tempOutput.path
            ]

            let result = try await ProcessRunner.run(
                executableURL: ffmpeg,
                arguments: arguments,
                timeout: 300,
                progressHandler: progressHandler
            )
            return result.exitCode == 0 && FileManager.default.fileExists(atPath: tempOutput.path)
        } catch {
            return false
        }
    }

    private func tryNativeExport(input url: URL, output tempOutput: URL, item: OptimizationItem, appState: AppState) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard (try? await asset.load(.isReadable)) ?? false else { return false }

        let preset = Preferences.shared.videoQuality.nativePreset
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            return false
        }

        session.outputURL = tempOutput
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        let progressTask = Task { @MainActor [session] in
            while true {
                guard session.status == .exporting || session.status == .waiting else { break }
                appState.replaceItem(item.id, with: OptimizationItem(
                    id: item.id, fileName: item.fileName,
                    fileSize: item.fileSize, optimizedSize: nil,
                    sourceURL: item.sourceURL, status: .processing(Double(session.progress))
                ))
                try? await Task.sleep(for: .seconds(0.25))
            }
        }

        defer { progressTask.cancel() }

        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            session.exportAsynchronously {
                continuation.resume(returning: FileManager.default.fileExists(atPath: tempOutput.path))
            }
        }
    }

}
