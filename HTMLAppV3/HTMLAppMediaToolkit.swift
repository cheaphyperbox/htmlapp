import Foundation
import UIKit
import CoreImage
import PDFKit

/// Performs bounded file-backed media processing without transporting image
/// pixels or PDF contents through large JavaScript bridge messages.
enum HTMLAppMediaToolkit {
    enum MediaError: LocalizedError {
        case invalidFile, unsupported, processingFailed
        var errorDescription: String? {
            switch self {
            case .invalidFile: return "Choose a valid local imported file within this saved app."
            case .unsupported: return "This media type or filter is not supported."
            case .processingFailed: return "The file could not be processed."
            }
        }
    }

    static func filterImage(source: URL, root: URL, effect: String) throws -> [String: Any] {
        guard let size = (try? source.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
              size > 0 && size <= 30_000_000,
              let image = CIImage(contentsOf: source),
              image.extent.width > 0, image.extent.height > 0,
              max(image.extent.width, image.extent.height) <= 8000 else {
            throw MediaError.invalidFile
        }
        let output: CIImage
        switch effect {
        case "mono":
            let filter = CIFilter(name: "CIPhotoEffectMono")
            filter?.setValue(image, forKey: kCIInputImageKey)
            guard let value = filter?.outputImage else { throw MediaError.processingFailed }
            output = value
        case "sepia":
            let filter = CIFilter(name: "CISepiaTone")
            filter?.setValue(image, forKey: kCIInputImageKey)
            filter?.setValue(0.85, forKey: kCIInputIntensityKey)
            guard let value = filter?.outputImage else { throw MediaError.processingFailed }
            output = value
        case "invert":
            let filter = CIFilter(name: "CIColorInvert")
            filter?.setValue(image, forKey: kCIInputImageKey)
            guard let value = filter?.outputImage else { throw MediaError.processingFailed }
            output = value
        case "blur":
            let filter = CIFilter(name: "CIGaussianBlur")
            filter?.setValue(image, forKey: kCIInputImageKey)
            filter?.setValue(5.0, forKey: kCIInputRadiusKey)
            guard let value = filter?.outputImage else { throw MediaError.processingFailed }
            output = value.cropped(to: image.extent)
        default: throw MediaError.unsupported
        }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let result = context.jpegRepresentation(
            of: output.cropped(to: image.extent),
            colorSpace: CGColorSpaceCreateDeviceRGB(), options: [:]),
              result.count <= 30_000_000 else {
            throw MediaError.processingFailed
        }
        let relative = "native-outputs/images/" + UUID().uuidString + ".jpg"
        let destination = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try result.write(to: destination, options: .atomic)
        return ["url": relative, "mimeType": "image/jpeg", "size": result.count]
    }

    static func inspectPDF(source: URL) throws -> [String: Any] {
        guard let size = (try? source.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
              size > 0 && size <= 25_000_000,
              let pdf = PDFDocument(url: source) else { throw MediaError.invalidFile }
        let pageCount = pdf.pageCount
        let text = (0..<min(pageCount, 12)).compactMap {
            pdf.page(at: $0)?.string
        }.joined(separator: "\n\n")
        return [
            "pageCount": pageCount,
            "text": String(text.prefix(12_000)),
            "truncated": pageCount > 12 || text.count > 12_000
        ]
    }
}
