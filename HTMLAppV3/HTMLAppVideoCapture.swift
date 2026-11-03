import Foundation
import UIKit
import UniformTypeIdentifiers

/// User-initiated video capture with an app-scoped file result.
/// The captured movie is never serialized into a WKWebView message.
@MainActor
final class HTMLAppVideoCapture: NSObject, UIImagePickerControllerDelegate,
    UINavigationControllerDelegate {
    private let root: URL
    private let maximumDuration: TimeInterval
    private var completion: ((Result<[String: Any], Error>) -> Void)?
    private var finished = false

    init(root: URL, options: [String: Any],
         completion: @escaping (Result<[String: Any], Error>) -> Void) {
        self.root = root.standardizedFileURL
        let input = (options["maxDuration"] as? NSNumber)?.doubleValue ?? 60
        maximumDuration = max(3, min(300, input.isFinite ? input : 60))
        self.completion = completion
        super.init()
    }

    func present(from presenter: UIViewController) throws {
        guard UIImagePickerController.isSourceTypeAvailable(.camera),
              UIImagePickerController.availableMediaTypes(for: .camera)?
                .contains(UTType.movie.identifier) == true else {
            throw VideoError.unavailable
        }
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.movie.identifier]
        picker.cameraCaptureMode = .video
        picker.videoMaximumDuration = maximumDuration
        picker.videoQuality = .typeMedium
        picker.allowsEditing = false
        picker.modalPresentationStyle = .fullScreen
        presenter.present(picker, animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard !finished else { return }
        guard let source = info[.mediaURL] as? URL else {
            finish(.failure(VideoError.missingMedia))
            return
        }
        let size = ((try? source.resourceValues(forKeys: [.fileSizeKey]))?.fileSize) ?? 0
        guard size > 0 && size <= 150_000_000 else {
            finish(.failure(VideoError.sizeLimit))
            return
        }
        let ext = ["mov", "mp4"].contains(source.pathExtension.lowercased())
            ? source.pathExtension.lowercased() : "mov"
        let relative = "native-imports/videos/" + UUID().uuidString + "." + ext
        let destination = root.appendingPathComponent(relative)
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: destination)
            finish(.success([
                "url": relative,
                "name": destination.lastPathComponent,
                "mimeType": ext == "mp4" ? "video/mp4" : "video/quicktime",
                "size": size
            ]))
        } catch {
            finish(.failure(error))
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        finish(.failure(VideoError.cancelled))
    }

    private func finish(_ result: Result<[String: Any], Error>) {
        guard !finished else { return }
        finished = true
        completion?(result)
        completion = nil
    }

    private enum VideoError: LocalizedError {
        case unavailable, missingMedia, sizeLimit, cancelled
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Camera video recording is unavailable on this device."
            case .missingMedia: return "The camera did not return a movie."
            case .sizeLimit: return "This movie exceeds the 150 MB saved-app limit."
            case .cancelled: return "Video capture was cancelled."
            }
        }
    }
}
