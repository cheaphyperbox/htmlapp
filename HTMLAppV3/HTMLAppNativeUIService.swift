import UIKit
import Foundation

/// Optional native iOS controls for generated HTMLApps. The host is the
/// presenter and returns a structured result; no HTML can take ownership of
/// arbitrary UIKit views or display an unbounded sequence of system modals.
@MainActor
enum HTMLAppNativeUIService {
    private static var lastPresentedAt: [String: Date] = [:]

    private static func presenter(for appID: String) -> UIViewController? {
        guard appID != "PREVIEW" else { return nil }
        let now = Date()
        guard now.timeIntervalSince(lastPresentedAt[appID] ?? .distantPast) >= 1 else { return nil }
        guard let controller = UIViewController.htmlAppTopViewController else { return nil }
        lastPresentedAt[appID] = now
        return controller
    }

    static func alert(args: [String: Any], appID: String, menu: Bool,
                      completion: @escaping @MainActor ([String: Any]?) -> Void) -> Bool {
        guard let presenter = presenter(for: appID) else { return false }
        let title = String((args["title"] as? String ?? "").prefix(160))
        let message = String((args["message"] as? String ?? "").prefix(800))
        let actions = (args["actions"] as? [[String: Any]] ?? [
            ["id": "ok", "title": "OK"]
        ])
        guard (1...6).contains(actions.count) else { return false }
        let alert = UIAlertController(title: title, message: message,
                                      preferredStyle: menu ? .actionSheet : .alert)
        for (index, entry) in actions.enumerated() {
            guard let label = entry["title"] as? String,
                  !label.isEmpty && label.count <= 80 else { return false }
            let name = String((entry["id"] as? String ?? String(index)).prefix(80))
            let style: UIAlertAction.Style
            switch entry["style"] as? String {
            case "cancel": style = .cancel
            case "destructive": style = .destructive
            default: style = .default
            }
            alert.addAction(UIAlertAction(title: label, style: style) { _ in
                completion(["id": name, "index": index, "cancelled": style == .cancel])
            })
        }
        if menu {
            alert.popoverPresentationController?.sourceView = presenter.view
            alert.popoverPresentationController?.sourceRect = CGRect(
                x: presenter.view.bounds.midX, y: presenter.view.bounds.maxY - 2,
                width: 1, height: 1
            )
        }
        presenter.present(alert, animated: true)
        return true
    }

    static func datePicker(args: [String: Any], appID: String,
                           completion: @escaping @MainActor ([String: Any]) -> Void) -> Bool {
        guard let presenter = presenter(for: appID) else { return false }
        let sheet = HTMLAppDatePickerSheet(args: args, completion: completion)
        sheet.modalPresentationStyle = .pageSheet
        sheet.isModalInPresentation = true
        if #available(iOS 16.0, *) {
            sheet.sheetPresentationController?.detents = [.medium()]
        }
        presenter.present(sheet, animated: true)
        return true
    }
}

@MainActor
private final class HTMLAppDatePickerSheet: UIViewController {
    private let picker = UIDatePicker()
    private let titleText: String
    private var callback: (([String: Any]) -> Void)?
    private let mode: UIDatePicker.Mode

    init(args: [String: Any], completion: @escaping @MainActor ([String: Any]) -> Void) {
        titleText = String((args["title"] as? String ?? "Choose a date").prefix(160))
        callback = completion
        switch args["mode"] as? String {
        case "date": mode = .date
        case "time": mode = .time
        default: mode = .dateAndTime
        }
        super.init(nibName: nil, bundle: nil)
        if let stamp = args["timestampMS"] as? NSNumber {
            picker.date = Date(timeIntervalSince1970: stamp.doubleValue / 1000)
        } else if let iso = args["value"] as? String,
                  let date = ISO8601DateFormatter().date(from: iso) {
            picker.date = date
        }
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        picker.datePickerMode = mode
        picker.preferredDatePickerStyle = .wheels
        let heading = UILabel()
        heading.text = titleText
        heading.font = .preferredFont(forTextStyle: .headline)
        heading.adjustsFontForContentSizeCategory = true
        heading.textAlignment = .center
        heading.numberOfLines = 2

        let cancel = UIButton(type: .system)
        cancel.setTitle("Cancel", for: .normal)
        cancel.addAction(UIAction { [weak self] _ in self?.finish(nil) }, for: .touchUpInside)
        let done = UIButton(type: .system)
        done.setTitle("Done", for: .normal)
        done.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        done.addAction(UIAction { [weak self] _ in self?.finish(self?.picker.date) }, for: .touchUpInside)
        let buttons = UIStackView(arrangedSubviews: [cancel, UIView(), done])
        buttons.axis = .horizontal
        buttons.distribution = .equalSpacing

        let stack = UIStackView(arrangedSubviews: [heading, picker, buttons])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20)
        ])
    }

    private func finish(_ date: Date?) {
        guard let callback else { return }
        self.callback = nil
        let result: [String: Any]
        if let date {
            let iso = ISO8601DateFormatter().string(from: date)
            result = ["cancelled": false, "value": iso, "timestampMS": date.timeIntervalSince1970 * 1000]
        } else {
            result = ["cancelled": true]
        }
        dismiss(animated: true) { callback(result) }
    }
}
