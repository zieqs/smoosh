import Foundation
import AVFoundation

enum VideoQuality: String, Codable, CaseIterable, Sendable {
    case fast = "fast"
    case low = "low"
    case medium = "medium"
    case high = "high"

    var displayName: String {
        switch self {
        case .fast: "Fast"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    var ffmpegVideoArgs: [String] {
        switch self {
        case .fast:
            #if arch(arm64)
            return ["-vcodec", "h264_videotoolbox", "-q:v", "50", "-tag:v", "avc1"]
            #else
            return ["-vcodec", "libx264", "-crf", "28", "-preset", "veryfast", "-tag:v", "avc1"]
            #endif
        case .low:
            return ["-vcodec", "libx264", "-crf", "25", "-preset", "slower", "-tag:v", "avc1"]
        case .medium:
            return ["-vcodec", "libx264", "-crf", "22", "-preset", "slower", "-tag:v", "avc1"]
        case .high:
            return ["-vcodec", "libx264", "-crf", "19", "-preset", "slower", "-tag:v", "avc1"]
        }
    }

    var nativePreset: String {
        switch self {
        case .fast, .low: AVAssetExportPresetLowQuality
        case .medium: AVAssetExportPresetMediumQuality
        case .high: AVAssetExportPresetHighestQuality
        }
    }
}

enum PDFQuality: String, Codable, CaseIterable, Sendable {
    case low = "low"
    case medium = "medium"
    case high = "high"

    var displayName: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    var dpi: Int {
        switch self {
        case .low: 96
        case .medium: 150
        case .high: 300
        }
    }

    var downsample: Bool { dpi < 300 }
    var passThroughJPEG: Bool { !downsample }
}

@Observable
final class Preferences {
    static let shared = Preferences()

    var videoQuality: VideoQuality {
        didSet {
            UserDefaults.standard.set(videoQuality.rawValue, forKey: "videoQuality")
        }
    }

    var pdfQuality: PDFQuality {
        didSet {
            UserDefaults.standard.set(pdfQuality.rawValue, forKey: "pdfQuality")
        }
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: "videoQuality"),
           let quality = VideoQuality(rawValue: raw) {
            videoQuality = quality
        } else {
            videoQuality = .medium
        }
        if let raw = UserDefaults.standard.string(forKey: "pdfQuality"),
           let quality = PDFQuality(rawValue: raw) {
            pdfQuality = quality
        } else {
            pdfQuality = .medium
        }
    }
}
