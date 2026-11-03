import UIKit
import Foundation

/// Foreground, user-initiated capture. Output is a file in this saved app's
/// sandbox; no image bytes or hidden Photo Library access cross the JS bridge.
@MainActor
final class HTMLAppCameraCapture: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let root: URL
    private let camera: String
    private let quality: CGFloat
    private let maxDimension: CGFloat
    private var completion: ((Result<[String: Any], Error>) -> Void)?
    private var finished = false

    init(root: URL, options: [String: Any],
         completion: @escaping (Result<[String: Any], Error>) -> Void) {
        self.root = root
        camera = options["camera"] as? String == "front" ? "front" : "back"
        quality = CGFloat(max(0.25, min(1, (options["quality"] as? NSNumber)?.doubleValue ?? 0.84)))
        maxDimension = CGFloat(max(512, min(4096, (options["maxDimension"] as? Int) ?? 2400)))
        self.completion = completion
        super.init()
    }

    func present(from controller: UIViewController) throws {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            throw NSError(domain: "HTMLAppCamera", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "This device has no available native camera."])
        }
        let device: UIImagePickerController.CameraDevice = camera == "front" ? .front : .rear
        guard UIImagePickerController.isCameraDeviceAvailable(device) else {
            throw NSError(domain: "HTMLAppCamera", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Requested camera is unavailable."])
        }
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .camera
        picker.cameraDevice = device
        picker.allowsEditing = false
        picker.modalPresentationStyle = .fullScreen
        controller.present(picker, animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard !finished else { return }
        guard let original = info[.originalImage] as? UIImage else {
            finish(.failure(NSError(domain: "HTMLAppCamera", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Camera returned no photo."])))
            return
        }
        let larger = max(original.size.width, original.size.height)
        let scale = larger > 0 ? min(1, maxDimension / larger) : 1
        let image: UIImage
        if scale < 1 {
            let size = CGSize(width: max(1, original.size.width * scale),
                              height: max(1, original.size.height * scale))
            image = UIGraphicsImageRenderer(size: size).image { _ in
                original.draw(in: CGRect(origin: .zero, size: size))
            }
        } else {
            image = original
        }
        guard let data = image.jpegData(compressionQuality: quality),
              data.count > 0, data.count <= 22_000_000 else {
            finish(.failure(NSError(domain: "HTMLAppCamera", code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Photo could not be encoded within the app size limit."])))
            return
        }
        let relative = "native-imports/photos/camera-" + UUID().uuidString + ".jpg"
        let destination = root.appendingPathComponent(relative)
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            finish(.success([
                "url": relative,
                "name": destination.lastPathComponent,
                "mimeType": "image/jpeg",
                "size": data.count,
                "width": image.size.width,
                "height": image.size.height
            ]))
        } catch {
            finish(.failure(error))
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        finish(.failure(NSError(domain: "HTMLAppCamera", code: 5,
            userInfo: [NSLocalizedDescriptionKey: "Camera capture cancelled."])))
    }

    private func finish(_ result: Result<[String: Any], Error>) {
        guard !finished else { return }
        finished = true
        completion?(result)
        completion = nil
    }
}
