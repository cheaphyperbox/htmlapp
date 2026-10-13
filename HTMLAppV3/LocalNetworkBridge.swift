import Foundation
import WebKit
import Security

/// Gives saved HTML apps a native path to private-LAN HTTP(S) and WebSocket
/// endpoints. This keeps normal browser APIs working while avoiding WKWebView's
/// local-file CORS limitations. For private/local HTTPS and WSS endpoints only,
/// normal iOS trust is attempted first. If the only missing piece is trust in the
/// presented local certificate chain, HTMLApp may use that presented chain as a
/// connection-scoped trust anchor; hostname/IP and certificate validity checks
/// are still enforced by Security.framework.
final class HTMLLocalNetworkBridge: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionWebSocketDelegate {
    private weak var webView: WKWebView?
    private weak var permissionCoordinator: NativePermissionCoordinator?

    private var session: URLSession!
    private var fetchTasks: [String: URLSessionDataTask] = [:]
    private var socketTasks: [String: URLSessionWebSocketTask] = [:]
    private var socketIDsByTask: [Int: String] = [:]
    private var closedSockets: Set<String> = []

    init(webView: WKWebView, permissionCoordinator: NativePermissionCoordinator?) {
        self.webView = webView
        self.permissionCoordinator = permissionCoordinator
        super.init()

        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 180
        configuration.waitsForConnectivity = false
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    }

    deinit {
        session?.invalidateAndCancel()
    }

    func shutdown() {
        for task in fetchTasks.values { task.cancel() }
        fetchTasks.removeAll()
        for task in socketTasks.values {
            task.cancel(with: .goingAway, reason: nil)
        }
        socketTasks.removeAll()
        socketIDsByTask.removeAll()
        closedSockets.removeAll()
        session.invalidateAndCancel()
    }

    @MainActor
    func handle(_ body: [String: Any]) {
        guard let action = body["action"] as? String else { return }

        switch action {
        case "fetch":
            guard let id = body["id"] as? String else { return }
            withLocalNetworkPermission(id: id) { [weak self] in
                self?.startFetch(id: id, body: body)
            }

        case "fetchCancel":
            guard let id = body["id"] as? String else { return }
            fetchTasks.removeValue(forKey: id)?.cancel()

        case "wsOpen":
            guard let id = body["id"] as? String else { return }
            withLocalNetworkPermission(id: id, isSocket: true) { [weak self] in
                self?.openSocket(id: id, body: body)
            }

        case "wsSend":
            guard let id = body["id"] as? String else { return }
            sendSocket(id: id, body: body)

        case "wsClose":
            guard let id = body["id"] as? String else { return }
            closeSocket(id: id, body: body)

        default:
            break
        }
    }

    @MainActor
    private func withLocalNetworkPermission(id: String, isSocket: Bool = false, action: @escaping @MainActor () -> Void) {
        guard let permissionCoordinator else {
            sendFailure(id: id, code: "bridge_unavailable", message: "Local network bridge is unavailable.", socket: isSocket)
            return
        }

        permissionCoordinator.requestHTMLPermission(.localNetwork) { [weak self] allowed in
            guard let self else { return }
            guard allowed else {
                self.sendFailure(
                    id: id,
                    code: "permission_denied",
                    message: "Local Network permission was denied for this HTML app.",
                    socket: isSocket
                )
                return
            }
            action()
        }
    }

    // MARK: - Fetch

    private func startFetch(id: String, body: [String: Any]) {
        guard let rawURL = body["url"] as? String,
              let url = URL(string: rawURL),
              Self.isAllowedLocalURL(url, schemes: ["http", "https"]) else {
            sendFetchResult(id: id, payload: [
                "ok": false,
                "code": "invalid_local_url",
                "message": "HTMLApp only proxies private/local HTTP(S) addresses."
            ])
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = (body["method"] as? String ?? "GET").uppercased()
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = max(1, min(body["timeout"] as? Double ?? 45, 180))

        if let headers = body["headers"] as? [String: String] {
            for (name, value) in headers {
                let lower = name.lowercased()
                if lower == "host" || lower == "content-length" || lower == "connection" { continue }
                request.setValue(value, forHTTPHeaderField: name)
            }
        } else if let headerPairs = body["headers"] as? [[String]] {
            for pair in headerPairs where pair.count >= 2 {
                let name = pair[0]
                let lower = name.lowercased()
                if lower == "host" || lower == "content-length" || lower == "connection" { continue }
                request.setValue(pair[1], forHTTPHeaderField: name)
            }
        }

        if let encoded = body["bodyBase64"] as? String, !encoded.isEmpty {
            guard let data = Data(base64Encoded: encoded) else {
                sendFetchResult(id: id, payload: [
                    "ok": false,
                    "code": "invalid_body",
                    "message": "The request body could not be decoded."
                ])
                return
            }
            request.httpBody = data
        }

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            self.fetchTasks.removeValue(forKey: id)

            if let error = error as NSError? {
                let code = error.code == NSURLErrorCancelled ? "cancelled" : "network_error"
                self.sendFetchResult(id: id, payload: [
                    "ok": false,
                    "code": code,
                    "message": self.friendlyNetworkError(error, url: url)
                ])
                return
            }

            guard let http = response as? HTTPURLResponse else {
                self.sendFetchResult(id: id, payload: [
                    "ok": false,
                    "code": "invalid_response",
                    "message": "The local server returned an invalid response."
                ])
                return
            }

            let responseData = data ?? Data()
            guard responseData.count <= 64 * 1024 * 1024 else {
                self.sendFetchResult(id: id, payload: [
                    "ok": false,
                    "code": "response_too_large",
                    "message": "The local response exceeded HTMLApp's 64 MB in-memory bridge limit."
                ])
                return
            }

            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                headers[String(describing: key)] = String(describing: value)
            }

            self.sendFetchResult(id: id, payload: [
                "ok": true,
                "status": http.statusCode,
                "statusText": HTTPURLResponse.localizedString(forStatusCode: http.statusCode),
                "url": http.url?.absoluteString ?? url.absoluteString,
                "headers": headers,
                "bodyBase64": responseData.base64EncodedString()
            ])
        }

        fetchTasks[id] = task
        task.resume()
    }

    private func sendFetchResult(id: String, payload: [String: Any]) {
        callJavaScript(function: "__htmlappLocalNetworkFetchResult", arguments: [id, payload])
    }

    // MARK: - WebSocket

    private func openSocket(id: String, body: [String: Any]) {
        guard let rawURL = body["url"] as? String,
              let url = URL(string: rawURL),
              Self.isAllowedLocalURL(url, schemes: ["ws", "wss"]) else {
            sendSocketEvent(id: id, event: "error", payload: [
                "code": "invalid_local_url",
                "message": "HTMLApp only proxies private/local WebSocket addresses."
            ])
            sendSocketEvent(id: id, event: "close", payload: ["code": 1006, "reason": "Invalid local WebSocket URL", "wasClean": false])
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 45

        if let protocols = body["protocols"] as? [String], !protocols.isEmpty {
            request.setValue(protocols.joined(separator: ", "), forHTTPHeaderField: "Sec-WebSocket-Protocol")
        }

        let task = session.webSocketTask(with: request)
        socketTasks[id] = task
        socketIDsByTask[task.taskIdentifier] = id
        closedSockets.remove(id)
        task.resume()
        receiveNext(id: id, task: task)
    }

    private func sendSocket(id: String, body: [String: Any]) {
        guard let task = socketTasks[id] else {
            sendSocketEvent(id: id, event: "error", payload: ["message": "WebSocket is not connected."])
            return
        }

        let message: URLSessionWebSocketTask.Message
        if let text = body["text"] as? String {
            message = .string(text)
        } else if let encoded = body["base64"] as? String, let data = Data(base64Encoded: encoded) {
            message = .data(data)
        } else {
            sendSocketEvent(id: id, event: "error", payload: ["message": "Unsupported WebSocket message type."])
            return
        }

        task.send(message) { [weak self] error in
            guard let self, let error else { return }
            DispatchQueue.main.async {
                self.sendSocketEvent(id: id, event: "error", payload: ["message": error.localizedDescription])
            }
        }
    }

    private func closeSocket(id: String, body: [String: Any]) {
        guard let task = socketTasks[id] else { return }
        let rawCode = body["code"] as? Int ?? 1000
        let code = URLSessionWebSocketTask.CloseCode(rawValue: rawCode) ?? .normalClosure
        let reason = (body["reason"] as? String)?.data(using: .utf8)
        task.cancel(with: code, reason: reason)
    }

    private func receiveNext(id: String, task: URLSessionWebSocketTask) {
        task.receive { [weak self, weak task] result in
            guard let self, let task else { return }
            DispatchQueue.main.async {
                guard self.socketTasks[id] === task, !self.closedSockets.contains(id) else { return }
                switch result {
                case .success(.string(let text)):
                    self.sendSocketEvent(id: id, event: "message", payload: ["kind": "text", "data": text])
                    self.receiveNext(id: id, task: task)

                case .success(.data(let data)):
                    self.sendSocketEvent(id: id, event: "message", payload: ["kind": "binary", "base64": data.base64EncodedString()])
                    self.receiveNext(id: id, task: task)

                case .failure(let error):
                    self.sendSocketEvent(id: id, event: "error", payload: ["message": self.friendlyNetworkError(error as NSError, url: task.originalRequest?.url)])
                    self.finishSocket(id: id, code: 1006, reason: error.localizedDescription, wasClean: false)
                }
            }
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        guard let id = socketIDsByTask[webSocketTask.taskIdentifier], socketTasks[id] === webSocketTask else { return }
        sendSocketEvent(id: id, event: "open", payload: ["protocol": `protocol` ?? ""])
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        guard let id = socketIDsByTask[webSocketTask.taskIdentifier] else { return }
        let text = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        finishSocket(id: id, code: closeCode.rawValue, reason: text, wasClean: true)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = socketIDsByTask[task.taskIdentifier],
              socketTasks[id]?.taskIdentifier == task.taskIdentifier else { return }
        guard let error else { return }
        sendSocketEvent(id: id, event: "error", payload: [
            "message": friendlyNetworkError(error as NSError, url: task.originalRequest?.url)
        ])
        finishSocket(id: id, code: 1006, reason: error.localizedDescription, wasClean: false)
    }

    private func finishSocket(id: String, code: Int, reason: String, wasClean: Bool) {
        guard !closedSockets.contains(id) else { return }
        closedSockets.insert(id)
        if let task = socketTasks.removeValue(forKey: id) {
            socketIDsByTask.removeValue(forKey: task.taskIdentifier)
        }
        sendSocketEvent(id: id, event: "close", payload: [
            "code": code,
            "reason": reason,
            "wasClean": wasClean
        ])
    }

    private func sendSocketEvent(id: String, event: String, payload: [String: Any]) {
        callJavaScript(function: "__htmlappLocalNetworkSocketEvent", arguments: [id, event, payload])
    }

    private func sendFailure(id: String, code: String, message: String, socket: Bool) {
        if socket {
            sendSocketEvent(id: id, event: "error", payload: ["code": code, "message": message])
            sendSocketEvent(id: id, event: "close", payload: ["code": 1006, "reason": message, "wasClean": false])
        } else {
            sendFetchResult(id: id, payload: ["ok": false, "code": code, "message": message])
        }
    }

    // MARK: - Local TLS trust

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let url = task.currentRequest?.url ?? task.originalRequest?.url
        let challengeHost = challenge.protectionSpace.host.lowercased()
        guard let url,
              Self.isAllowedLocalURL(url, schemes: ["https", "wss"]),
              Self.isLocalHost(challengeHost),
              url.host?.lowercased() == challengeHost else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Keep standard system trust whenever it already succeeds.
        if SecTrustEvaluateWithError(trust, nil) {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }

        // The local bridge is already restricted to loopback/RFC1918/link-local
        // hosts and gated by HTMLApp's per-app Local Network permission. For those
        // hosts only, trust the certificate chain presented by that endpoint for
        // this connection, then re-run Apple's SSL policy checks. This handles a
        // private CA or self-signed local certificate without globally weakening
        // TLS and without disabling host/IP or validity-date verification.
        guard Self.evaluatePresentedLocalTrust(trust) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    private static func evaluatePresentedLocalTrust(_ trust: SecTrust) -> Bool {
        let count = SecTrustGetCertificateCount(trust)
        guard count > 0,
              let presentedAnchor = SecTrustGetCertificateAtIndex(trust, count - 1),
              SecTrustSetAnchorCertificates(trust, [presentedAnchor] as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, false) == errSecSuccess else {
            return false
        }
        return SecTrustEvaluateWithError(trust, nil)
    }

    // MARK: - Helpers

    private func friendlyNetworkError(_ error: NSError, url: URL?) -> String {
        if error.domain == NSURLErrorDomain {
            switch error.code {
            case NSURLErrorServerCertificateUntrusted,
                 NSURLErrorServerCertificateHasBadDate,
                 NSURLErrorServerCertificateHasUnknownRoot,
                 NSURLErrorServerCertificateNotYetValid,
                 NSURLErrorSecureConnectionFailed:
                return "TLS trust failed for \(url?.host ?? "the local server"). HTMLApp accepted the presented local trust chain only if its certificate was valid for this host/IP and date. Check the certificate SAN and the device/server clocks."
            case NSURLErrorCannotConnectToHost:
                return "Could not connect to \(url?.host ?? "the local server"). Make sure the device is on the same LAN and Local Network access is enabled for HTMLApp."
            case NSURLErrorTimedOut:
                return "The local server timed out."
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return "The local network connection is unavailable or was interrupted."
            case NSURLErrorCancelled:
                return "The request was cancelled."
            default:
                break
            }
        }
        return error.localizedDescription
    }

    private static func isAllowedLocalURL(_ url: URL, schemes: Set<String>) -> Bool {
        guard let scheme = url.scheme?.lowercased(), schemes.contains(scheme),
              let host = url.host?.lowercased(), !host.isEmpty else { return false }
        return isLocalHost(host)
    }

    private static func isLocalHost(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") { return true }
        if host == "::1" || host.hasPrefix("fe80:") || host.hasPrefix("fc") || host.hasPrefix("fd") { return true }

        let parts = host.split(separator: ".")
        guard parts.count == 4,
              let a = Int(parts[0]), let b = Int(parts[1]),
              let c = Int(parts[2]), let d = Int(parts[3]),
              (0...255).contains(a), (0...255).contains(b),
              (0...255).contains(c), (0...255).contains(d) else { return false }

        if a == 10 || a == 127 { return true }
        if a == 169 && b == 254 { return true }
        if a == 192 && b == 168 { return true }
        if a == 172 && (16...31).contains(b) { return true }
        return false
    }

    private func callJavaScript(function: String, arguments: [Any]) {
        guard JSONSerialization.isValidJSONObject(arguments),
              let data = try? JSONSerialization.data(withJSONObject: arguments),
              let json = String(data: data, encoding: .utf8) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript("window.\(function) && window.\(function).apply(null, \(json));")
        }
    }
}

enum HTMLLocalNetworkScript {
    static let source = #"""
    (() => {
      if (window.__htmlappLocalNetworkBridgeInstalled) return;
      window.__htmlappLocalNetworkBridgeInstalled = true;

      const handler = () => window.webkit?.messageHandlers?.htmlappNetwork;
      const NativeFetch = window.fetch.bind(window);
      const NativeWebSocket = window.WebSocket;
      let sequence = 0;
      const pendingFetches = new Map();
      const localSockets = new Map();

      const localHost = (hostname) => {
        const host = String(hostname || '').toLowerCase().replace(/^\[|\]$/g, '');
        if (host === 'localhost' || host.endsWith('.localhost') || host.endsWith('.local')) return true;
        if (host === '::1' || host.startsWith('fe80:') || host.startsWith('fc') || host.startsWith('fd')) return true;
        const p = host.split('.').map(Number);
        if (p.length !== 4 || p.some(v => !Number.isInteger(v) || v < 0 || v > 255)) return false;
        return p[0] === 10 ||
          p[0] === 127 ||
          (p[0] === 169 && p[1] === 254) ||
          (p[0] === 192 && p[1] === 168) ||
          (p[0] === 172 && p[1] >= 16 && p[1] <= 31);
      };

      const localURL = (raw, protocols) => {
        try {
          const url = new URL(String(raw), document.baseURI);
          return protocols.includes(url.protocol) && localHost(url.hostname);
        } catch (_) {
          return false;
        }
      };

      const bytesToBase64 = (bytes) => {
        let binary = '';
        const step = 32768;
        for (let i = 0; i < bytes.length; i += step) {
          binary += String.fromCharCode.apply(null, bytes.subarray(i, Math.min(bytes.length, i + step)));
        }
        return btoa(binary);
      };

      const base64ToBytes = (value) => {
        const binary = atob(String(value || ''));
        const out = new Uint8Array(binary.length);
        for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
        return out;
      };

      window.__htmlappLocalNetworkFetchResult = (id, payload) => {
        const item = pendingFetches.get(id);
        if (!item) return;
        pendingFetches.delete(id);
        item.cleanup?.();

        if (!payload?.ok) {
          if (payload?.code === 'cancelled') {
            item.reject(new DOMException('The operation was aborted.', 'AbortError'));
          } else {
            const error = new TypeError(payload?.message || 'Local network request failed.');
            error.code = payload?.code || 'network_error';
            item.reject(error);
          }
          return;
        }

        const status = Number(payload.status || 200);
        const noBody = status === 204 || status === 205 || status === 304 || item.method === 'HEAD';
        const body = noBody ? null : base64ToBytes(payload.bodyBase64 || '');
        try {
          const response = new Response(body, {
            status,
            statusText: String(payload.statusText || ''),
            headers: payload.headers || {}
          });
          try { Object.defineProperty(response, 'url', { configurable: true, value: String(payload.url || item.url) }); } catch (_) {}
          item.resolve(response);
        } catch (error) {
          item.reject(error);
        }
      };

      window.fetch = async (input, init = undefined) => {
        let request;
        try {
          request = new Request(input, init);
        } catch (_) {
          return NativeFetch(input, init);
        }

        if (!localURL(request.url, ['http:', 'https:']) || !handler()) {
          return NativeFetch(input, init);
        }

        if (request.signal?.aborted) {
          throw new DOMException('The operation was aborted.', 'AbortError');
        }

        const id = `lan-fetch-${Date.now()}-${++sequence}`;
        const headers = {};
        request.headers.forEach((value, key) => { headers[key] = value; });

        let bodyBase64 = '';
        if (request.method !== 'GET' && request.method !== 'HEAD') {
          const buffer = await request.clone().arrayBuffer();
          bodyBase64 = bytesToBase64(new Uint8Array(buffer));
        }

        return new Promise((resolve, reject) => {
          const abort = () => {
            handler()?.postMessage({ action: 'fetchCancel', id });
            pendingFetches.delete(id);
            reject(new DOMException('The operation was aborted.', 'AbortError'));
          };
          if (request.signal) request.signal.addEventListener('abort', abort, { once: true });

          pendingFetches.set(id, {
            resolve,
            reject,
            method: request.method,
            url: request.url,
            cleanup: () => request.signal?.removeEventListener('abort', abort)
          });

          handler()?.postMessage({
            action: 'fetch',
            id,
            url: request.url,
            method: request.method,
            headers,
            bodyBase64
          });
        });
      };

      class LocalSocket extends EventTarget {
        constructor(url, protocols) {
          super();
          this.url = String(url);
          this.readyState = 0;
          this.bufferedAmount = 0;
          this.extensions = '';
          this.protocol = '';
          this.binaryType = 'blob';
          this.onopen = null;
          this.onmessage = null;
          this.onerror = null;
          this.onclose = null;
          this.__id = `lan-ws-${Date.now()}-${++sequence}`;
          localSockets.set(this.__id, this);

          const list = Array.isArray(protocols) ? protocols.map(String) :
            (protocols == null || protocols === '' ? [] : [String(protocols)]);
          handler()?.postMessage({ action: 'wsOpen', id: this.__id, url: this.url, protocols: list });
        }

        send(data) {
          if (this.readyState !== 1) throw new DOMException('WebSocket is not open.', 'InvalidStateError');
          if (typeof data === 'string') {
            handler()?.postMessage({ action: 'wsSend', id: this.__id, text: data });
            return;
          }
          if (data instanceof ArrayBuffer) {
            handler()?.postMessage({ action: 'wsSend', id: this.__id, base64: bytesToBase64(new Uint8Array(data)) });
            return;
          }
          if (ArrayBuffer.isView(data)) {
            handler()?.postMessage({
              action: 'wsSend',
              id: this.__id,
              base64: bytesToBase64(new Uint8Array(data.buffer, data.byteOffset, data.byteLength))
            });
            return;
          }
          if (data instanceof Blob) {
            data.arrayBuffer().then(buffer => {
              if (this.readyState === 1) {
                handler()?.postMessage({ action: 'wsSend', id: this.__id, base64: bytesToBase64(new Uint8Array(buffer)) });
              }
            }).catch(() => {});
            return;
          }
          throw new TypeError('Unsupported WebSocket message type.');
        }

        close(code = 1000, reason = '') {
          if (this.readyState === 2 || this.readyState === 3) return;
          this.readyState = 2;
          handler()?.postMessage({ action: 'wsClose', id: this.__id, code: Number(code) || 1000, reason: String(reason || '') });
        }

        __emit(event) {
          this.dispatchEvent(event);
          const fn = this['on' + event.type];
          if (typeof fn === 'function') {
            try { fn.call(this, event); } catch (error) { setTimeout(() => { throw error; }, 0); }
          }
        }
      }

      Object.defineProperties(LocalSocket.prototype, {
        CONNECTING: { value: 0 },
        OPEN: { value: 1 },
        CLOSING: { value: 2 },
        CLOSED: { value: 3 }
      });

      window.__htmlappLocalNetworkSocketEvent = (id, type, payload = {}) => {
        const socket = localSockets.get(id);
        if (!socket) return;

        if (type === 'open') {
          socket.readyState = 1;
          socket.protocol = String(payload.protocol || '');
          socket.__emit(new Event('open'));
          return;
        }

        if (type === 'message') {
          let data;
          if (payload.kind === 'binary') {
            const bytes = base64ToBytes(payload.base64 || '');
            data = socket.binaryType === 'arraybuffer' ? bytes.buffer : new Blob([bytes]);
          } else {
            data = String(payload.data ?? '');
          }
          socket.__emit(new MessageEvent('message', { data }));
          return;
        }

        if (type === 'error') {
          const event = new Event('error');
          try { Object.defineProperty(event, 'message', { value: String(payload.message || 'WebSocket error') }); } catch (_) {}
          socket.__emit(event);
          return;
        }

        if (type === 'close') {
          socket.readyState = 3;
          localSockets.delete(id);
          let event;
          try {
            event = new CloseEvent('close', {
              code: Number(payload.code || 1006),
              reason: String(payload.reason || ''),
              wasClean: !!payload.wasClean
            });
          } catch (_) {
            event = new Event('close');
          }
          socket.__emit(event);
        }
      };

      if (NativeWebSocket) {
        const WrappedWebSocket = new Proxy(NativeWebSocket, {
          construct(target, args, newTarget) {
            const url = args[0];
            if (localURL(url, ['ws:', 'wss:']) && handler()) {
              return new LocalSocket(url, args[1]);
            }
            return Reflect.construct(target, args, newTarget === WrappedWebSocket ? target : newTarget);
          }
        });
        try { window.WebSocket = WrappedWebSocket; } catch (_) {}
      }

      window.HTMLAppLocalNetwork = Object.freeze({
        isLocalURL: (url) => localURL(url, ['http:', 'https:', 'ws:', 'wss:']),
        fetch: (input, init) => window.fetch(input, init)
      });
    })();
    """#
}
