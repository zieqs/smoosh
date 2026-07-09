import Foundation
import UniformTypeIdentifiers
import ImageIO

struct PDFRasterizationOptimizer {
    private static let dpi: CGFloat = 200
    private static let jpegQuality: CGFloat = 0.7

    static func optimize(fileAt inputURL: URL, outputURL: URL) -> Bool {
        guard let document = CGPDFDocument(inputURL as CFURL) else { return false }
        let scale = dpi / 72.0
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(outputURL as CFURL, mediaBox: nil, nil) else { return false }

        for pageNum in 1...document.numberOfPages {
            guard let page = document.page(at: pageNum) else { continue }
            var mediaBox = page.getBoxRect(.mediaBox)
            let width = Int(mediaBox.width * scale)
            let height = Int(mediaBox.height * scale)

            let bitmap = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
            guard let bitmap else { continue }

            bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
            bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
            bitmap.interpolationQuality = .high
            bitmap.scaleBy(x: scale, y: scale)
            bitmap.drawPDFPage(page)

            guard let cgImage = bitmap.makeImage() else { continue }

            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                data as CFMutableData,
                UTType.jpeg.identifier as CFString,
                1, nil
            ) else { continue }

            let options: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: jpegQuality
            ]
            CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { continue }

            guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
                  let jpegImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else { continue }

            context.beginPage(mediaBox: &mediaBox)
            context.draw(jpegImage, in: mediaBox)
            context.endPage()
        }

        return true
    }
}
