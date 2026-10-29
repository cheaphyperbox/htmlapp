import Foundation
import UIKit
import PencilKit

/// Foreground native drawing sheet. Produces an app-scoped PNG rather than a
/// multi-megabyte data URL crossing WKWebView.
@MainActor
final class HTMLAppDrawingPresenter: UIViewController {
    private let root: URL
    private let onFinish: (Result<[String: Any], Error>) -> Void
    private let canvas = PKCanvasView()
    private let toolPicker = PKToolPicker()
    private var finished = false

    init(root: URL, onFinish: @escaping (Result<[String: Any], Error>) -> Void) {
        self.root = root
        self.onFinish = onFinish
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Drawing"
        view.backgroundColor = .systemBackground
        canvas.backgroundColor = .white
        canvas.isOpaque = true
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .black, width: 5)
        canvas.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(canvas)
        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save, target: self, action: #selector(save))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        toolPicker.setVisible(true, forFirstResponder: canvas)
        toolPicker.addObserver(canvas)
        canvas.becomeFirstResponder()
    }

    @objc private func cancel() {
        finish(.failure(NSError(domain: "HTMLAppDrawing", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Drawing cancelled."])))
    }

    @objc private func save() {
        let area = canvas.bounds
        guard area.width > 0, area.height > 0,
              let png = canvas.drawing.image(from: area, scale: min(2, UIScreen.main.scale)).pngData(),
              png.count <= 12_000_000 else {
            finish(.failure(NSError(domain: "HTMLAppDrawing", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Drawing could not be saved safely."])))
            return
        }
        do {
            let relative = "native-imports/drawings/" + UUID().uuidString + ".png"
            let url = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url, options: .atomic)
            finish(.success(["url": relative, "size": png.count, "mimeType": "image/png"]))
        } catch { finish(.failure(error)) }
    }

    private func finish(_ result: Result<[String: Any], Error>) {
        guard !finished else { return }
        finished = true
        toolPicker.removeObserver(canvas)
        dismiss(animated: true) { [onFinish] in onFinish(result) }
    }
}
