import UIKit

/// Retained until a real UIKit color picker is dismissed. Only user-initiated
/// presentation is allowed by the native UI service.
@MainActor
final class HTMLAppColorPickerSession: NSObject, UIColorPickerViewControllerDelegate {
    private var completion: (([String: Any]) -> Void)?
    private var picker: UIColorPickerViewController?

    func present(from controller: UIViewController, options: [String: Any],
                 completion: @escaping ([String: Any]) -> Void) {
        self.completion = completion
        let picker = UIColorPickerViewController()
        picker.delegate = self
        picker.supportsAlpha = options["alpha"] as? Bool ?? false
        if let color = options["hex"] as? String,
           let parsed = Self.parseHex(color) {
            picker.selectedColor = parsed
        }
        picker.modalPresentationStyle = .formSheet
        self.picker = picker
        controller.present(picker, animated: true)
    }

    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        let color = viewController.selectedColor.resolvedColor(with: .current)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let hex = String(format: "#%02X%02X%02X",
                         Int(round(red * 255)), Int(round(green * 255)),
                         Int(round(blue * 255)))
        let result: [String: Any] = [
            "cancelled": false, "hex": hex, "alpha": Double(alpha)
        ]
        let callback = completion
        completion = nil
        picker = nil
        callback?(result)
    }

    private static func parseHex(_ text: String) -> UIColor? {
        guard text.count == 7, text.first == "#",
              let number = Int(text.dropFirst(), radix: 16) else { return nil }
        return UIColor(red: CGFloat((number >> 16) & 255) / 255,
                       green: CGFloat((number >> 8) & 255) / 255,
                       blue: CGFloat(number & 255) / 255, alpha: 1)
    }
}
