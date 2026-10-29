import Foundation
import UIKit
import VisionKit

/// User-triggered, foreground document scanner. Scans remain in the selected
/// saved app's SourceCache; no image bytes travel through JS postMessage.
@MainActor
final class HTMLAppDocumentScanner: NSObject, VNDocumentCameraViewControllerDelegate {
    private let root: URL
    private let completion: (Result<[[String: Any]], Error>) -> Void
    private var finished = false

    init(root: URL, completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        self.root = root
        self.completion = completion
    }

    func present(from controller: UIViewController) throws {
        guard VNDocumentCameraViewController.isSupported else {
            throw NSError(domain: "HTMLAppDocumentScanner", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Document scanning is not supported on this device."])
        }
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = self
        controller.present(scanner, animated: true)
    }

    nonisolated func documentCameraViewController(
        _ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
        Task { @MainActor in
            controller.dismiss(animated: true)
            guard !finished else { return }
            let root = self.root
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    var results: [[String: Any]] = []
                    for index in 0..<min(scan.pageCount, 20) {
                        guard let data = scan.imageOfPage(at: index).jpegData(compressionQuality: 0.84),
                              data.count <= 22_000_000 else {
                            throw NSError(domain: "HTMLAppDocumentScanner", code: 2,
                                userInfo: [NSLocalizedDescriptionKey: "A scan page could not be encoded safely."])
                        }
                        let relative = "native-imports/scans/" + UUID().uuidString + ".jpg"
                        let destination = root.appendingPathComponent(relative)
                        try FileManager.default.createDirectory(
                            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try data.write(to: destination, options: .atomic)
                        results.append(["url": relative, "mimeType": "image/jpeg",
                                        "size": data.count, "page": index + 1])
                    }
                    DispatchQueue.main.async {
                        Task { @MainActor in self.finish(.success(results)) }
                    }
                } catch {
                    DispatchQueue.main.async {
                        Task { @MainActor in self.finish(.failure(error)) }
                    }
                }
            }
        }
    }

    nonisolated func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        Task { @MainActor in
            controller.dismiss(animated: true)
            finish(.failure(NSError(domain: "HTMLAppDocumentScanner", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Document scan cancelled."])))
        }
    }

    nonisolated func documentCameraViewController(
        _ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
        Task { @MainActor in
            controller.dismiss(animated: true)
            finish(.failure(error))
        }
    }

    private func finish(_ result: Result<[[String: Any]], Error>) {
        guard !finished else { return }
        finished = true
        completion(result)
    }
}
