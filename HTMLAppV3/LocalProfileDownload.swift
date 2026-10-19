import Foundation
import UIKit
import Network

@MainActor
final class LocalProfileDownload {
    static let shared = LocalProfileDownload()
    private var generation = UUID()
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var background: UIBackgroundTaskIdentifier = .invalid
    private var expiry: Task<Void, Never>?
    private var completion: ((Result<URL, Error>) -> Void)?

    func start(profile: Data, completion: @escaping (Result<URL, Error>) -> Void) {
        stop()
        self.completion = completion
        let generation = self.generation
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            let listener = try NWListener(using: parameters)
            self.listener = listener
            let path = "/\(UUID().uuidString)/HTMLApp.mobileconfig"
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                guard let self, self.generation == generation, self.connections.count < 8 else { connection.cancel(); return }
                self.connections.append(connection)
                connection.start(queue: .main)
                self.receive(connection, accumulated: Data(), path: path, profile: profile)
                }
            }
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                Task { @MainActor in
                guard let self, self.generation == generation else { return }
                switch state {
                case .ready:
                    guard let port = listener?.port,
                          let url = URL(string: "http://127.0.0.1:\(port.rawValue)\(path)") else { return }
                    self.background = UIApplication.shared.beginBackgroundTask(withName: "Download Web Clip Profile") { [weak self] in self?.stop() }
                    let callback = self.completion; self.completion = nil; callback?(.success(url))
                case .failed(let error):
                    let callback = self.completion; self.completion = nil; self.stop(); callback?(.failure(error))
                default: break
                }
                }
            }
            listener.start(queue: .main)
            expiry = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { return }
                let callback = self?.completion
                self?.completion = nil; self?.stop()
                callback?(.failure(NSError(domain: "ProfileDownload", code: 1, userInfo: [NSLocalizedDescriptionKey: "Profile download timed out. Return to HTMLApp and try again, or export the profile."])))
            }
        } catch { self.completion = nil; stop(); completion(.failure(error)) }
    }
    private func receive(_ connection: NWConnection, accumulated: Data, path: String, profile: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, finished, error in
            Task { @MainActor in
            guard let self, self.connections.contains(where: { $0 === connection }) else { connection.cancel(); return }
            let request = accumulated + (data ?? Data())
            guard error == nil, request.count <= 8192 else { self.close(connection); return }
            if let text = String(data: request, encoding: .utf8), text.contains("\r\n\r\n") {
                let response = HTMLAppLocalProfileResponse.response(request: text, path: path, profile: profile)
                connection.send(content: response, completion: .contentProcessed { [weak self] _ in Task { @MainActor in self?.close(connection) } })
            } else if !finished { self.receive(connection, accumulated: request, path: path, profile: profile) }
            else { self.close(connection) }
            }
        }
    }
    private func close(_ connection: NWConnection) {
        connection.cancel(); connections.removeAll { $0 === connection }
    }
    func stop() {
        generation = UUID()
        listener?.cancel(); listener = nil
        connections.forEach { $0.cancel() }; connections.removeAll()
        expiry?.cancel(); expiry = nil
        if background != .invalid { UIApplication.shared.endBackgroundTask(background); background = .invalid }
    }
}
