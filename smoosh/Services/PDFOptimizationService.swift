import Foundation
import UniformTypeIdentifiers

private let GS_FONT_PATH = [
    "\(NSHomeDirectory())/Library/Fonts",
    "/Library/Fonts",
    "/System/Library/Fonts",
    "/System/Library/Fonts/Supplemental",
].filter { FileManager.default.fileExists(atPath: $0) }.joined(separator: ":")

private func gsArgs(
    input: String,
    output: String,
    quality: PDFQuality
) -> [String] {
    var args: [String] = [
        "-dNOPAUSE", "-dBATCH", "-dSAFER",
        "-dOptimize=true",
        "-dCompatibilityLevel=1.6",
        "-sDEVICE=pdfwrite",
        "-dCompressFonts=true", "-dSubsetFonts=true", "-dEmbedAllFonts=true",
        "-dCompressPages=true", "-dCompressStreams=true", "-dDetectDuplicateImages=true",
        "-dColorConversionStrategy=/RGB", "-dConvertCMYKImagesToRGB=true",
        "-dProcessColorModel=/DeviceRGB",
        "-dPreserveAnnots=true", "-dPreserveOverprintSettings=true",
        "-dAutoRotatePages=/None",
        "-dParseDSCComments=false",
        "-dDoThumbnails=false",
        "-dFastWebView=false",
        "-dDownsampleColorImages=\(quality.downsample)",
        "-dDownsampleGrayImages=\(quality.downsample)",
        "-dDownsampleMonoImages=\(quality.downsample)",
        "-dColorImageDownsampleThreshold=1.0",
        "-dColorImageDownsampleType=/Bicubic",
        "-dGrayImageDownsampleThreshold=1.0",
        "-dGrayImageDownsampleType=/Bicubic",
        "-dMonoImageDownsampleType=/Bicubic",
        "-dAutoFilterColorImages=false",
        "-dAutoFilterGrayImages=false",
        "-dColorImageFilter=/DCTEncode",
        "-dGrayImageFilter=/DCTEncode",
        "-dMonoImageFilter=/CCITTFaxEncode",
        "-dPassThroughJPEGImages=\(quality.passThroughJPEG)",
        "-dPassThroughJPXImages=\(quality.passThroughJPEG)",
        "-sFONTPATH=\(GS_FONT_PATH)",
    ]

    if quality.downsample {
        args += [
            "-dColorImageResolution=\(quality.dpi)",
            "-dGrayImageResolution=\(quality.dpi)",
            "-dMonoImageResolution=\(max(quality.dpi, 300))",
        ]
    }

    args += ["-sOutputFile=\(output)", "-f", input]
    return args
}

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

            appState.replaceItem(item.id, with: OptimizationItem(
                id: item.id, fileName: url.lastPathComponent,
                fileSize: item.fileSize, optimizedSize: nil,
                sourceURL: url, status: .processing(0)
            ))

            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            let tempOutput = tempDir.appendingPathComponent(outputURL.lastPathComponent)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            defer { try? FileManager.default.removeItem(at: tempDir) }

            guard let gs = BinaryLocator.url(for: "gs") else {
                appState.replaceItem(item.id, with: OptimizationItem(
                    id: item.id, fileName: url.lastPathComponent,
                    fileSize: item.fileSize, optimizedSize: nil,
                    sourceURL: url, status: .failed("Ghostscript not found")
                ))
                return
            }

            let args = gsArgs(input: url.path, output: tempOutput.path, quality: Preferences.shared.pdfQuality)

            do {
                let result = try await ProcessRunner.run(
                    executableURL: gs,
                    arguments: args,
                    timeout: 120
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
                        sourceURL: url, status: .failed("GS exited with code \(result.exitCode)")
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
        }
    }
}
