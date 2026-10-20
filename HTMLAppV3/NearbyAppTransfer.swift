import SwiftUI
import MultipeerConnectivity

final class NearbyAppTransfer: NSObject, ObservableObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate {
    @Published var status = "Keep Nearby Transfer open on both devices, then connect to the device you recognize."
    @Published var connected = false
    @Published var active = false
    @Published var busy = false
    @Published var received: URL?
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
        session.disconnect(); active = false; connected = false; busy = false
        if let outbound { try? FileManager.default.removeItem(at: outbound) }; outbound = nil
    }
    func send(_ url: URL) {
        guard !busy, let peer = session.connectedPeers.first else { return }
        outbound = url; busy = true; status = "Sending encrypted backup…"
        session.sendResource(at: url, withName: "HTMLApp.htmlapp.zip", toPeer: peer) { [weak self] error in
            DispatchQueue.main.async {
                self?.busy = false
                self?.status = error == nil ? "Transfer sent. The other device must confirm import." : "Transfer failed: \(error!.localizedDescription)"
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
            self.status = state == .connected ? "Connected to \(peerID.displayName). Choose Send, or wait for their backup." : "Connection changed. Keep both devices nearby and this screen open."
            if state == .notConnected { self.busy = false }
        }
    }
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) { stream.close() }
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        DispatchQueue.main.async { self.busy = true; self.status = "Receiving encrypted backup from \(peerID.displayName)…" }
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
    @StateObject private var transfer = NearbyAppTransfer()
    @State private var browse = false
    @State private var confirmImport = false
    @State private var chooseApps = false
    @State private var selectedAppIDs: Set<String>

    init(appIDs: Set<String>) {
        _selectedAppIDs = State(initialValue: appIDs)
    }

    private var isReceiveOnly: Bool { selectedAppIDs.isEmpty }

    var body: some View {
        List {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nearby device transfer")
                            .font(.headline)
                        Text("Encrypted and direct. iOS uses Bluetooth, peer-to-peer Wi-Fi, or local Wi-Fi depending on availability.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.tint)
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: transfer.connected ? "checkmark.circle.fill" : "info.circle")
                        .foregroundStyle(transfer.connected ? .green : .secondary)
                    Text(transfer.status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    browse = true
                } label: {
                    Label(
                        transfer.connected ? "Connected to Nearby Device" : "Find Nearby Device",
                        systemImage: transfer.connected ? "checkmark.circle.fill" : "dot.radiowaves.left.and.right"
                    )
                }
                .disabled(!transfer.active || transfer.connected || transfer.busy)
            } header: {
                Text("Connection")
            } footer: {
                Text("Keep Nearby Transfer open on both devices while connecting and transferring.")
            }

            Section("Send Apps") {
                Button { chooseApps = true } label: {
                    Label(selectedAppIDs.isEmpty ? "Choose Apps to Send" : "Change Selected Apps (\(selectedAppIDs.count))", systemImage: "square.stack.3d.up")
                }
                if selectedAppIDs.count == 1,
                   let selected = store.apps.first(where: { selectedAppIDs.contains($0.id) }) {
                    Label(selected.name, systemImage: "app.fill").foregroundStyle(.secondary)
                }
                Button { sendSelectedApps() } label: {
                    Label(selectedAppIDs.count == 1 ? "Send App" : "Send \(selectedAppIDs.count) Apps", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedAppIDs.isEmpty || !transfer.connected || transfer.busy)
                if !transfer.connected {
                    Text("Choose your apps, connect to a nearby device above, then tap Send App. The receiver confirms import.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("Receive") {
                if transfer.received == nil {
                    Label(
                        isReceiveOnly
                            ? "Connect to the sending device, then wait here for its backup."
                            : "You can also receive a backup from the connected device.",
                        systemImage: "square.and.arrow.down"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                } else {
                    Button("Review and Import Received Backup") {
                        confirmImport = true
                    }
                }
            }

            Section {
                Text("Transfers include selected apps, portable app data, icons, folder links, and supported cached resources. Provider credentials, permission grants, and device-private Keychain data are not transferred.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("What Moves")
            }

            if transfer.active {
                Section {
                    Button("Disconnect", role: .destructive) {
                        transfer.stop()
                    }
                }
            }
        }
        .navigationTitle("Nearby Transfer")
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
        .confirmationDialog(
            "Import this backup from the connected device?",
            isPresented: $confirmImport,
            titleVisibility: .visible
        ) {
            Button("Merge as New Copies") {
                guard let url = transfer.received else { return }
                do {
                    try store.importPortablePackage(from: url, replaceExisting: false)
                    transfer.status = "Imported as new copies. Existing apps were kept."
                } catch {
                    transfer.status = "Import failed: \(error.localizedDescription)"
                }
                try? FileManager.default.removeItem(at: url)
                transfer.received = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Existing apps are kept. Imported apps are added as new copies.")
        }
        .onAppear {
            transfer.start()
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
        do {
            let url = try store.createNearbyPackage(appIDs: selectedAppIDs)
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 100_000_000 else {
                try? FileManager.default.removeItem(at: url)
                transfer.status = "Backup exceeds 100 MB. Use Export and AirDrop instead."
                return
            }
            transfer.send(url)
        } catch {
            transfer.status = "Could not prepare apps: \(error.localizedDescription)"
        }
    }

}
