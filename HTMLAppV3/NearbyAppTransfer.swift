import SwiftUI
import MultipeerConnectivity

final class NearbyAppTransfer: NSObject, ObservableObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate {
    @Published var status = "Keep Nearby Transfer open on both devices, then connect to the device you recognize."
    @Published var connected = false
    @Published var active = false
    @Published var busy = false
    @Published var received: URL?
    @Published var recipientConfirmed = false
    @Published var sendFailed = false
    @Published var invitationName: String?
    private var invitation: ((Bool, MCSession?) -> Void)?
    let session = MCSession(peer: MCPeerID(displayName: String(UIDevice.current.name.prefix(50))), securityIdentity: nil, encryptionPreference: .required)
    private var advertiser: MCNearbyServiceAdvertiser?
    private var outbound: URL?

    override init() { super.init(); session.delegate = self }
    func start() {
        guard !active else { return }
        let advertiser = MCNearbyServiceAdvertiser(peer: session.myPeerID, discoveryInfo: nil, serviceType: "htmlapp-share")
        advertiser.delegate = self; advertiser.startAdvertisingPeer(); self.advertiser = advertiser
        active = true; status = "Visible nearby. Only accept a device you recognize."
    }
    func answer(_ accept: Bool) {
        invitation?(accept, accept ? session : nil); invitation = nil; invitationName = nil
    }
    func stop() {
        answer(false); advertiser?.stopAdvertisingPeer(); advertiser = nil
        session.disconnect(); active = false; connected = false; busy = false; recipientConfirmed = false
        if let outbound { try? FileManager.default.removeItem(at: outbound) }; outbound = nil
    }
    func send(_ url: URL) {
        guard !busy, let peer = session.connectedPeers.first else { return }
        outbound = url; busy = true; sendFailed = false; status = "Sending app without saved data…"
        session.sendResource(at: url, withName: "HTMLApp.htmlapp.zip", toPeer: peer) { [weak self] error in
            DispatchQueue.main.async {
                self?.busy = false
                self?.status = error == nil ? "Sent. Waiting for the other device to save the app…" : "Transfer failed: \(error!.localizedDescription)"
                if error != nil {
                    self?.sendFailed = true
                } else {
                    // Resource completion is not proof that import succeeded.
                    // Require an encrypted receipt from the receiving device.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 90) { [weak self] in
                        guard let self, self.active && !self.recipientConfirmed else { return }
                        self.status = "The receiving device hasn't confirmed saving yet."
                        self.sendFailed = true
                    }
                }
                try? FileManager.default.removeItem(at: url); self?.outbound = nil
            }
        }
    }
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async {
            guard self.session.connectedPeers.isEmpty, self.invitation == nil else { invitationHandler(false, nil); return }
            self.invitation = invitationHandler; self.invitationName = peerID.displayName
        }
    }
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async { self.status = "Nearby discovery failed. Check Local Network permission: \(error.localizedDescription)"; self.active = false }
    }
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.connected = !session.connectedPeers.isEmpty
            self.status = state == .connected ? "Connected to \(peerID.displayName)! You can send your selected apps now." : "Not connected yet. Keep this screen open on both devices."
            if state == .notConnected { self.busy = false }
        }
    }
    private static let importReceipt = Data("HTMLAPP_IMPORTED_V1".utf8)
    func confirmImport() {
        guard let peer = session.connectedPeers.first else { return }
        try? session.send(Self.importReceipt, toPeers: [peer], with: .reliable)
    }
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard data == Self.importReceipt, session.connectedPeers.contains(peerID) else { return }
        DispatchQueue.main.async {
            self.recipientConfirmed = true
            self.status = "The other device saved your app!"
        }
    }
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) { stream.close() }
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        DispatchQueue.main.async { self.busy = true; self.status = "Receiving app from \(peerID.displayName)…" }
    }
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        do {
            if let error { throw error }
            guard resourceName == "HTMLApp.htmlapp.zip", let localURL,
                  let size = try localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 100_000_000 else { throw HTMLAppPackageError.invalidArchive }
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("Nearby-\(UUID().uuidString).zip")
            try FileManager.default.copyItem(at: localURL, to: destination)
            DispatchQueue.main.async {
                if let old = self.received { try? FileManager.default.removeItem(at: old) }
                self.received = destination; self.busy = false; self.status = "Backup received. Review and import as new copies below."
            }
        } catch { DispatchQueue.main.async { self.busy = false; self.status = "Receive failed: \(error.localizedDescription)" } }
    }
}

struct NearbyPeerBrowser: UIViewControllerRepresentable {
    let session: MCSession
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator { dismiss() } }
    func makeUIViewController(context: Context) -> MCBrowserViewController {
        let browser = MCBrowserViewController(serviceType: "htmlapp-share", session: session)
        browser.maximumNumberOfPeers = 1; browser.delegate = context.coordinator
        return browser
    }
    func updateUIViewController(_ uiViewController: MCBrowserViewController, context: Context) {}
    final class Coordinator: NSObject, MCBrowserViewControllerDelegate {
        let close: () -> Void
        init(close: @escaping () -> Void) { self.close = close }
        func browserViewControllerDidFinish(_ browserViewController: MCBrowserViewController) { close() }
        func browserViewControllerWasCancelled(_ browserViewController: MCBrowserViewController) { close() }
    }
}

struct NearbyAppTransferView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("developerMode") private var developerMode = false
    @StateObject private var transfer = NearbyAppTransfer()
    @State private var browse = false
    @State private var startedSending = false
    @State private var importing = false
    @State private var transferError: String?
    @Environment(\.dismiss) private var dismiss
    @State private var chooseApps = false
    @State private var selectedAppIDs: Set<String>

    init(appIDs: Set<String>) {
        _selectedAppIDs = State(initialValue: appIDs)
    }

    private var isReceiveOnly: Bool { selectedAppIDs.isEmpty }

    var body: some View {
        List {
            if isReceiveOnly {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: importing ? "square.and.arrow.down.fill" :
                            transfer.connected ? "checkmark.circle.fill" : "iphone.gen3.radiowaves.left.and.right")
                            .font(.system(size: 42))
                            .foregroundStyle(transfer.connected ? Color.green : Color.accentColor)
                        Text(importing ? "Saving your app…" :
                            transfer.connected ? "Connected! Waiting for the app…" : "Ready to receive")
                            .font(.title2.weight(.bold))
                        Text("Ask the sender to choose this device. Tap Accept when its name appears. The app will be saved in your Library automatically.")
                            .font(.body)
                        if importing { ProgressView() }
                        Text(transfer.status).font(.footnote).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 22)
                } header: {
                    Text("Receive an app")
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(selectedAppIDs.count == 1 ? "One app ready to share" : "\(selectedAppIDs.count) apps ready to share",
                              systemImage: "app.badge")
                            .font(.title3.bold())
                        if selectedAppIDs.count == 1,
                           let app = store.apps.first(where: { selectedAppIDs.contains($0.id) }) {
                            HStack(spacing: 12) {
                                AppIconView(app: app, size: 46)
                                Text(app.name).font(.headline)
                            }
                        }
                        Button("Change apps") { chooseApps = true }
                            .font(.subheadline)
                        Divider()
                        Text(transfer.connected ? "Connected! Sending automatically…" : "Tap Find device, then choose the receiving phone.")
                            .font(.headline)
                        if transfer.busy { ProgressView() }
                        Button { browse = true } label: {
                            Label(transfer.connected ? "Connected to receiver" : "Find receiving phone",
                                  systemImage: "dot.radiowaves.left.and.right")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!transfer.active || transfer.connected || transfer.busy || startedSending)
                        Text(transfer.status).font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 18)
                } header: {
                    Text("Send an app")
                } footer: {
                    Text("Both devices must keep HTMLApp open. Once connected, your app sends automatically and this screen closes after the receiver saves it.")
                }
            }
            if let transferError {
                Section {
                    Label(transferError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    if isReceiveOnly {
                        Button("Keep waiting") { self.transferError = nil }
                    } else {
                        Button("Try sending again") {
                            self.transferError = nil
                            startedSending = false
                            sendSelectedApps()
                        }
                        .disabled(!transfer.connected || transfer.busy)
                    }
                }
            }
            if developerMode {
                Section("Connection details") {
                    Text("Encrypted local MultipeerConnectivity over Bluetooth and/or Wi-Fi. Only accept devices you recognize.")
                        .font(.footnote)
                    Button("Disconnect", role: .destructive) {
                        transfer.stop()
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(isReceiveOnly ? "Receive App" : "Send App")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $browse) {
            NearbyPeerBrowser(session: transfer.session)
        }
        .sheet(isPresented: $chooseApps) {
            NavigationStack {
                List {
                    ForEach(store.orderedApps) { app in
                        Button {
                            if selectedAppIDs.contains(app.id) { selectedAppIDs.remove(app.id) }
                            else { selectedAppIDs.insert(app.id) }
                        } label: {
                            HStack(spacing: 12) {
                                AppIconView(app: app, size: 40)
                                Text(app.name).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: selectedAppIDs.contains(app.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedAppIDs.contains(app.id) ? Color.accentColor : Color.secondary)
                            }
                        }
                    }
                }
                .navigationTitle("Apps to Send")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { chooseApps = false } } }
            }
        }
        .alert(
            "Accept nearby connection?",
            isPresented: Binding(
                get: { transfer.invitationName != nil },
                set: { if !$0 { transfer.answer(false) } }
            )
        ) {
            Button("Accept") { transfer.answer(true) }
            Button("Decline", role: .cancel) { transfer.answer(false) }
        } message: {
            Text(transfer.invitationName ?? "Unknown device")
        }
        .onAppear {
            transfer.start()
        }
        .onChange(of: transfer.connected) { connected in
            if connected {
                // The sender should never have to press Done in the device browser.
                browse = false
                if !isReceiveOnly && !startedSending { sendSelectedApps() }
            } else if startedSending && !transfer.recipientConfirmed {
                startedSending = false
                transferError = "Connection lost. Keep both devices nearby, then try again."
            }
        }
        .onChange(of: transfer.received) { url in
            guard isReceiveOnly, let url, !importing else { return }
            importing = true
            Task { @MainActor in
                // Let the saving indicator render before importing larger packages.
                try? await Task.sleep(nanoseconds: 100_000_000)
                do {
                    try store.importPortablePackage(from: url, replaceExisting: false, includePersonalData: false)
                    transfer.confirmImport()
                    try? FileManager.default.removeItem(at: url)
                    transfer.received = nil
                    transfer.status = "App saved to Library!"
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    dismiss()
                } catch {
                    transferError = "Couldn't save the received app: \(error.localizedDescription)"
                    importing = false
                    try? FileManager.default.removeItem(at: url)
                    transfer.received = nil
                }
            }
        }
        .onChange(of: transfer.sendFailed) { failed in
            guard failed, !isReceiveOnly else { return }
            startedSending = false
            transferError = "The transfer didn't finish. Keep both devices nearby and try again."
        }
        .onChange(of: transfer.recipientConfirmed) { confirmed in
            guard confirmed, !isReceiveOnly else { return }
            Task {
                try? await Task.sleep(nanoseconds: 750_000_000)
                dismiss()
            }
        }
        .onChange(of: scenePhase) {
            if $0 == .background { transfer.stop() }
        }
        .onDisappear {
            if !browse && !chooseApps {
                transfer.stop()
                if let url = transfer.received {
                    try? FileManager.default.removeItem(at: url)
                    transfer.received = nil
                }
            }
        }
    }
    private func sendSelectedApps() {
        guard !selectedAppIDs.isEmpty, transfer.connected, !transfer.busy else { return }
        startedSending = true
        do {
            let url = try store.createNearbyPackage(appIDs: selectedAppIDs)
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 100_000_000 else {
                try? FileManager.default.removeItem(at: url)
                transferError = "This app is larger than 100 MB. Use Export and AirDrop."
                startedSending = false
                return
            }
            transfer.send(url)
        } catch {
            startedSending = false
            transferError = "Could not prepare app: \(error.localizedDescription)"
        }
    }

}
