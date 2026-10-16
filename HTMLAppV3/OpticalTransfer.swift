import SwiftUI
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

struct OpticalImportPayload: Identifiable, Equatable {
    let id = UUID()
    let fileName: String
    let html: String
    let app: SavedHTMLApp?
    let portableData: [String: String]?
    let widgets: [HTMLAppWidgetDefinition]?
    let backgroundJobs: [HTMLAppBackgroundFetchJob]?

    init(
        fileName: String,
        html: String,
        app: SavedHTMLApp? = nil,
        portableData: [String: String]? = nil,
        widgets: [HTMLAppWidgetDefinition]? = nil,
        backgroundJobs: [HTMLAppBackgroundFetchJob]? = nil
    ) {
        self.fileName = fileName
        self.html = html
        self.app = app
        self.portableData = portableData
        self.widgets = widgets
        self.backgroundJobs = backgroundJobs
    }
}

private struct OpticalEnvelope: Codable {
    let formatVersion: Int?
    let fileName: String?
    let html: String?
    let app: SavedHTMLApp?
    let portableData: [String: String]?
    let widgets: [HTMLAppWidgetDefinition]?
    let backgroundJobs: [HTMLAppBackgroundFetchJob]?

    init(fileName: String, html: String) {
        self.formatVersion = 1
        self.fileName = fileName
        self.html = html
        self.app = nil
        self.portableData = nil
        self.widgets = nil
        self.backgroundJobs = nil
    }

    init(app: SavedHTMLApp) {
        self.formatVersion = 4
        self.fileName = OpticalTransferCodec.safeFileName(app.name)
        self.html = nil
        self.app = app
        self.portableData = HTMLAppPortableDataStore.all(appID: app.id)
        self.widgets = HTMLAppWidgetStore.definitions(appID: app.id)
        self.backgroundJobs = HTMLAppBackgroundJobStore.jobs(appID: app.id)
    }
}

enum OpticalTransferCodec {
    static let frameInterval: TimeInterval = 0.15
    static let parityBlockSize = 10
    static let rawChunkSize = 550

    static func frames(for app: SavedHTMLApp) -> [String] {
        guard let payload = try? JSONEncoder().encode(OpticalEnvelope(app: app)) else { return [] }
        return frames(payload: payload)
    }

    static func frames(fileName: String, html: String) -> [String] {
        guard let payload = try? JSONEncoder().encode(OpticalEnvelope(fileName: fileName, html: html)) else { return [] }
        return frames(payload: payload)
    }

    private static func frames(payload: Data) -> [String] {
        let transferID = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8))
        let chunks = stride(from: 0, to: payload.count, by: rawChunkSize).map {
            payload.subdata(in: $0..<min($0 + rawChunkSize, payload.count))
        }
        guard !chunks.isEmpty else { return [] }

        var frames: [String] = []
        for blockStart in stride(from: 0, to: chunks.count, by: parityBlockSize) {
            let blockEnd = min(blockStart + parityBlockSize, chunks.count)
            for index in blockStart..<blockEnd {
                frames.append(makeFrame(transferID, "D", index, chunks.count, chunks[index]))
            }

            let block = Array(chunks[blockStart..<blockEnd])
            let maximumLength = block.map(\.count).max() ?? 0
            var parity = Data(repeating: 0, count: maximumLength)
            parity.withUnsafeMutableBytes { parityBuffer in
                guard let parityBytes = parityBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
                for chunk in block {
                    chunk.withUnsafeBytes { chunkBuffer in
                        guard let bytes = chunkBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
                        for offset in 0..<chunk.count { parityBytes[offset] ^= bytes[offset] }
                    }
                }
            }
            frames.append(makeFrame(transferID, "P", blockStart / parityBlockSize, chunks.count, parity))
        }
        return frames
    }

    private static func makeFrame(_ transferID: String, _ kind: String, _ index: Int, _ total: Int, _ payload: Data) -> String {
        "HAT1|\(transferID)|\(kind)|\(String(index, radix: 36))|\(String(total, radix: 36))|\(String(parityBlockSize, radix: 36))|\(payload.base64EncodedString())"
    }

    static func qrImage(for text: String, size: CGFloat = 900) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = max(1, floor(size / output.extent.width))
        let image = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = CIContext().createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    static func safeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        return (cleaned.isEmpty ? "HTMLApp" : cleaned) + ".html"
    }
}

@MainActor
final class OpticalFrameCollector: ObservableObject {
    @Published private(set) var receivedCount = 0
    @Published private(set) var totalExpected = 0
    @Published private(set) var status = "Point the camera at the sending device."
    @Published private(set) var completedPayload: OpticalImportPayload?

    private var transferID: String?
    private var chunks: [Int: Data] = [:]
    private var parity: [Int: Data] = [:]
    private var blockSize = OpticalTransferCodec.parityBlockSize

    var progress: Double {
        totalExpected == 0 ? 0 : min(1, Double(receivedCount) / Double(totalExpected))
    }

    func accept(_ string: String) {
        guard completedPayload == nil else { return }
        let parts = string.split(separator: "|", maxSplits: 6, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 7, parts[0] == "HAT1",
              let index = Int(parts[3], radix: 36),
              let total = Int(parts[4], radix: 36),
              let parsedBlockSize = Int(parts[5], radix: 36),
              let payload = Data(base64Encoded: parts[6]), total > 0 else { return }

        if transferID == nil {
            transferID = parts[1]
            totalExpected = total
            blockSize = max(1, parsedBlockSize)
        }
        guard transferID == parts[1], totalExpected == total else { return }

        if parts[2] == "D", chunks[index] == nil {
            chunks[index] = payload
            recover(blockIndex: index / blockSize)
        } else if parts[2] == "P", parity[index] == nil {
            parity[index] = payload
            recover(blockIndex: index)
        }

        receivedCount = chunks.count
        status = "Received \(receivedCount) of \(totalExpected) frames"
        if chunks.count == totalExpected { assemble() }
    }

    private func recover(blockIndex: Int) {
        guard let parityData = parity[blockIndex] else { return }
        let start = blockIndex * blockSize
        let end = min(start + blockSize, totalExpected)
        let missing = (start..<end).filter { chunks[$0] == nil }
        guard missing.count == 1 else { return }

        var recovered = parityData
        let recoveredLength = recovered.count
        recovered.withUnsafeMutableBytes { recoveredBuffer in
            guard let recoveredBytes = recoveredBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            for index in start..<end where index != missing[0] {
                guard let chunk = chunks[index] else { return }
                chunk.withUnsafeBytes { chunkBuffer in
                    guard let bytes = chunkBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
                    for offset in 0..<min(chunk.count, recoveredLength) { recoveredBytes[offset] ^= bytes[offset] }
                }
            }
        }

        if missing[0] == totalExpected - 1 {
            while recovered.last == 0 { recovered.removeLast() }
        }
        chunks[missing[0]] = recovered
    }

    private func assemble() {
        var data = Data()
        for index in 0..<totalExpected {
            guard let chunk = chunks[index] else { return }
            data.append(chunk)
        }
        guard let envelope = try? JSONDecoder().decode(OpticalEnvelope.self, from: data) else {
            status = "The complete transfer could not be decoded."
            return
        }

        if let app = envelope.app {
            status = "Transfer complete"
            completedPayload = OpticalImportPayload(
                fileName: envelope.fileName ?? OpticalTransferCodec.safeFileName(app.name),
                html: app.html,
                app: app,
                portableData: envelope.portableData,
                widgets: envelope.widgets,
                backgroundJobs: envelope.backgroundJobs
            )
        } else if let html = envelope.html {
            status = "Transfer complete"
            completedPayload = OpticalImportPayload(
                fileName: envelope.fileName ?? "HTMLApp.html",
                html: html
            )
        } else {
            status = "The complete transfer did not contain an HTMLApp."
        }
    }
}

struct OpticalSenderView: View {
    let app: SavedHTMLApp
    @Environment(\.dismiss) private var dismiss
    @State private var frames: [String] = []
    @State private var frameIndex = 0
    @State private var paused = false
    private let timer = Timer.publish(every: OpticalTransferCodec.frameInterval, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("Show this screen to the receiving device")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                if frames.isEmpty {
                    ProgressView("Preparing frames…")
                } else if let image = OpticalTransferCodec.qrImage(for: frames[frameIndex]) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(12)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(.horizontal)
                    ProgressView(value: Double(frameIndex + 1), total: Double(frames.count))
                        .padding(.horizontal)
                    Text("Frame \(frameIndex + 1) of \(frames.count) • Full HTMLApp envelope • Recovery enabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(paused ? "Resume" : "Pause") { paused.toggle() }
                        .buttonStyle(.borderedProminent)
                }
                Spacer(minLength: 0)
            }
            .padding(.top)
            .navigationTitle("Send \(app.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .onAppear { frames = OpticalTransferCodec.frames(for: app) }
            .onReceive(timer) { _ in
                guard !paused, !frames.isEmpty else { return }
                frameIndex = (frameIndex + 1) % frames.count
            }
        }
    }
}

struct OpticalReceiverView: View {
    let onReceive: (OpticalImportPayload) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var collector = OpticalFrameCollector()

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                OpticalScannerView { collector.accept($0) }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, dash: [12, 8]))
                            .padding(40)
                    }
                    .frame(maxHeight: 520)
                ProgressView(value: collector.progress)
                Text(collector.status).font(.headline).multilineTextAlignment(.center)
                if collector.totalExpected > 0 {
                    Text("\(Int(collector.progress * 100))% complete")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .navigationTitle("Receive HTMLApp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onChange(of: collector.completedPayload) { payload in
                guard let payload else { return }
                onReceive(payload)
                dismiss()
            }
        }
    }
}

private struct OpticalScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> OpticalScannerViewController {
        OpticalScannerViewController(onCode: onCode)
    }

    func updateUIViewController(_ uiViewController: OpticalScannerViewController, context: Context) {}
}

private final class OpticalScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let onCode: (String) -> Void
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var configured = false

    init(onCode: @escaping (String) -> Void) {
        self.onCode = onCode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        requestAndStart()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if session.isRunning { session.stopRunning() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func requestAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else { return }
                DispatchQueue.main.async { self?.configureAndStart() }
            }
        default:
            break
        }
    }

    private func configureAndStart() {
        if !configured {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.beginConfiguration()
            session.sessionPreset = .high
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                session.commitConfiguration()
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
            session.commitConfiguration()

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            view.layer.insertSublayer(layer, at: 0)
            previewLayer = layer
            configured = true
        }
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
            }
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        for object in metadataObjects {
            guard let qr = object as? AVMetadataMachineReadableCodeObject,
                  let value = qr.stringValue,
                  value.hasPrefix("HAT1|") else { continue }
            onCode(value)
        }
    }
}

struct ImportHTMLDestinationView: View {
    let payload: OpticalImportPayload
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { installNew() } label: {
                        Label("Install as New HTML App", systemImage: "plus.app.fill")
                    }
                    .disabled(working)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(payload.app?.name ?? payload.fileName)
                        if let summary = payload.app?.summary, !summary.isEmpty {
                            Text(summary).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(payload.app == nil ? "Legacy HTML transfer" : "Includes metadata, portable data, widgets, and background jobs")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if !store.orderedApps.isEmpty {
                    Section("Update an Existing App") {
                        ForEach(store.orderedApps) { app in
                            Button { update(app) } label: {
                                HStack(spacing: 12) {
                                    AppIconView(app: app, size: 44)
                                    Text(app.name).foregroundStyle(.primary)
                                    Spacer()
                                    if app.isFavorite == true {
                                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                                    }
                                }
                            }
                            .disabled(working)
                        }
                    }
                }
            }
            .navigationTitle("Import HTML")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .overlay { if working { ProgressView().controlSize(.large) } }
        }
    }

    private func installNew() {
        working = true
        Task {
            if let transferred = payload.app {
                await store.addTransferredApp(
                    transferred,
                    portableData: payload.portableData,
                    widgets: payload.widgets,
                    backgroundJobs: payload.backgroundJobs
                )
            } else {
                await store.add(
                    html: payload.html,
                    summary: "Imported from \(payload.fileName)"
                )
                store.notice = "HTML app imported."
            }
            dismiss()
        }
    }

    private func update(_ app: SavedHTMLApp) {
        working = true
        Task {
            await store.update(
                app,
                html: payload.html,
                summary: payload.app?.summary ?? app.summary
            )
            if let portableData = payload.portableData {
                HTMLAppPortableDataStore.replace(appID: app.id, values: portableData)
            }
            store.installTransferredIntegrations(
                appID: app.id,
                widgets: payload.widgets,
                backgroundJobs: payload.backgroundJobs
            )
            store.notice = "\(app.name) updated."
            dismiss()
        }
    }
}
