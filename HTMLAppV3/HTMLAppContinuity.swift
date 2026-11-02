import Foundation
import Network
import CryptoKit

struct HTMLAppRuntimeSnapshot: Codable {
    var appID: String
    var processSessionID: String
    var capturedAt: Date
    var html: String
    var scrollX: Double
    var scrollY: Double
    var fields: [[String: String]]
    var localStorage: [String: String]
    var sessionStorage: [String: String]
    var scrollRegions: [[String: String]]?
    var canvases: [[String: String]]?
    var media: [[String: String]]?
    var focusedSelector: String?
}

enum HTMLAppProcessSession {
    static let id = UUID().uuidString
    private static var coldRestoreDecisions = Set<String>()

    static func hasDecidedColdRestore(appID: String) -> Bool {
        coldRestoreDecisions.contains(appID)
    }

    static func markColdRestoreDecision(appID: String) {
        coldRestoreDecisions.insert(appID)
    }
}

enum HTMLAppRuntimeStateStore {
    private static let maxHTMLBytes = 3_500_000
    private static let queue = DispatchQueue(label: "com.mekabrine.htmlapp.runtime-state")
    private static let memoryLock = NSLock()
    private static var memory: [String: HTMLAppRuntimeSnapshot] = [:]

    private static func safeID(_ appID: String) -> String {
        let value = appID.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        return value.isEmpty ? "app" : value
    }

    private static func url(appID: String) -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HTMLApp/RuntimeState", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent(safeID(appID) + ".json")
    }

    static func save(appID: String, body: [String: Any]) {
        guard appID != "PREVIEW",
              let html = body["html"] as? String,
              html.utf8.count <= maxHTMLBytes else { return }

        func strings(_ value: Any?) -> [String: String] {
            guard let dictionary = value as? [String: Any] else {
                return value as? [String: String] ?? [:]
            }
            return dictionary.reduce(into: [:]) { result, pair in
                if let string = pair.value as? String { result[pair.key] = string }
            }
        }
        let rawFields = body["fields"] as? [[String: Any]] ?? []
        let fields: [[String: String]] = rawFields.prefix(1000).compactMap { item in
            guard let selector = item["selector"] as? String,
                  let kind = item["kind"] as? String,
                  let value = item["value"] as? String else { return nil }
            return ["selector": selector, "kind": kind, "value": value]
        }

        func stringRows(_ value: Any?, limit: Int) -> [[String: String]] {
            guard let rows = value as? [[String: Any]] else { return [] }
            return rows.prefix(limit).map { row in
                row.reduce(into: [String: String]()) { result, pair in
                    if let string = pair.value as? String { result[pair.key] = string }
                    else if let number = pair.value as? NSNumber { result[pair.key] = number.stringValue }
                }
            }
        }

        let snapshot = HTMLAppRuntimeSnapshot(
            appID: appID,
            processSessionID: HTMLAppProcessSession.id,
            capturedAt: Date(),
            html: html,
            scrollX: (body["scrollX"] as? NSNumber)?.doubleValue ?? 0,
            scrollY: (body["scrollY"] as? NSNumber)?.doubleValue ?? 0,
            fields: fields,
            localStorage: strings(body["localStorage"]),
            sessionStorage: strings(body["sessionStorage"]),
            scrollRegions: stringRows(body["scrollRegions"], limit: 200),
            canvases: stringRows(body["canvases"], limit: 8),
            media: stringRows(body["media"], limit: 20),
            focusedSelector: body["focusedSelector"] as? String
        )
        memoryLock.lock()
        memory[appID] = snapshot
        memoryLock.unlock()
        queue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url(appID: appID), options: .atomic)
        }
    }

    static func load(appID: String) -> HTMLAppRuntimeSnapshot? {
        memoryLock.lock()
        let cached = memory[appID]
        memoryLock.unlock()
        if let cached { return cached }
        let disk: HTMLAppRuntimeSnapshot? = queue.sync {
            guard let data = try? Data(contentsOf: url(appID: appID)),
                  let snapshot = try? JSONDecoder().decode(HTMLAppRuntimeSnapshot.self, from: data),
                  snapshot.appID == appID else { return nil }
            return snapshot
        }
        if let disk {
            memoryLock.lock()
            memory[appID] = disk
            memoryLock.unlock()
        }
        return disk
    }

    static func remove(appID: String) {
        memoryLock.lock()
        memory.removeValue(forKey: appID)
        memoryLock.unlock()
        queue.async { try? FileManager.default.removeItem(at: url(appID: appID)) }
    }

    static func restorationScript(_ snapshot: HTMLAppRuntimeSnapshot) -> String {
        guard let data = try? JSONEncoder().encode(snapshot),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return """
        (() => {
          const state = \(json);
          const restoreStorage = (storage, values) => {
            try {
              for (const [key, value] of Object.entries(values || {})) storage.setItem(key, value);
            } catch (_) {}
          };
          restoreStorage(localStorage, state.localStorage);
          restoreStorage(sessionStorage, state.sessionStorage);
          for (const item of state.fields || []) {
            try {
              const el = document.querySelector(item.selector);
              if (!el) continue;
              if (item.kind === 'checked') el.checked = item.value === 'true';
              else if (item.kind === 'html') el.innerHTML = item.value;
              else el.value = item.value;
              el.dispatchEvent(new Event('input', { bubbles: true }));
              el.dispatchEvent(new Event('change', { bubbles: true }));
            } catch (_) {}
          }
          for (const item of state.scrollRegions || []) {
            try {
              const el = document.querySelector(item.selector);
              if (el) {
                el.scrollLeft = Number(item.left || 0);
                el.scrollTop = Number(item.top || 0);
              }
            } catch (_) {}
          }
          for (const item of state.media || []) {
            try {
              const el = document.querySelector(item.selector);
              if (!el) continue;
              if (Number.isFinite(Number(item.currentTime))) el.currentTime = Number(item.currentTime);
              el.volume = Math.max(0, Math.min(1, Number(item.volume ?? 1)));
              el.muted = item.muted === 'true';
              el.playbackRate = Number(item.playbackRate || 1);
            } catch (_) {}
          }
          for (const item of state.canvases || []) {
            try {
              const canvas = document.querySelector(item.selector);
              if (!canvas || !item.dataURL) continue;
              const image = new Image();
              image.onload = () => {
                try {
                  const context = canvas.getContext('2d');
                  context?.clearRect(0, 0, canvas.width, canvas.height);
                  context?.drawImage(image, 0, 0, canvas.width, canvas.height);
                } catch (_) {}
              };
              image.src = item.dataURL;
            } catch (_) {}
          }
          requestAnimationFrame(() => {
            scrollTo(Number(state.scrollX || 0), Number(state.scrollY || 0));
            if (state.focusedSelector) {
              try { document.querySelector(state.focusedSelector)?.focus({preventScroll:true}); } catch (_) {}
            }
            window.__htmlappStateCaptureEnabled = true;
            window.dispatchEvent(new CustomEvent('htmlapp:state-restored'));
          });
        })();
        """
    }
}

enum HTMLAppRuntimeStateScript {
    static let source = #"""
    (() => {
      if (window.__htmlappStateCaptureInstalled) return;
      window.__htmlappStateCaptureInstalled = true;
      window.__htmlappStateCaptureEnabled = false;
      let dirty = true;
      const markDirty = () => { dirty = true; };
      addEventListener('input', markDirty, true);
      addEventListener('change', markDirty, true);
      addEventListener('scroll', markDirty, true);
      addEventListener('pointerup', markDirty, true);
      addEventListener('timeupdate', markDirty, true);

      try {
        for (const method of ['setItem','removeItem','clear']) {
          const original = Storage.prototype[method];
          Storage.prototype[method] = function(...args) {
            const result = original.apply(this, args);
            markDirty();
            return result;
          };
        }
      } catch (_) {}

      const stateObserver = new MutationObserver(markDirty);
      const observeState = () => {
        if (document.documentElement) {
          stateObserver.observe(document.documentElement, {
            subtree:true, childList:true, attributes:true, characterData:true
          });
        } else {
          setTimeout(observeState, 0);
        }
      };
      observeState();

      const selectorFor = (el) => {
        if (!el || el === document.body || el === document.documentElement) return null;
        if (el.id) return '#' + CSS.escape(el.id);
        const name = el.getAttribute?.('name');
        if (name) return el.tagName.toLowerCase() + '[name="' + CSS.escape(name) + '"]';
        const parts = [];
        let node = el;
        while (node && node.nodeType === 1 && node !== document.body && parts.length < 6) {
          const parent = node.parentElement;
          if (!parent) break;
          const siblings = Array.from(parent.children).filter(x => x.tagName === node.tagName);
          const nth = siblings.indexOf(node) + 1;
          parts.unshift(node.tagName.toLowerCase() + (siblings.length > 1 ? ':nth-of-type(' + nth + ')' : ''));
          node = parent;
        }
        return parts.length ? 'body > ' + parts.join(' > ') : null;
      };

      const storageObject = (storage) => {
        const out = {};
        let total = 0;
        try {
          for (let i = 0; i < storage.length && i < 500; i++) {
            const key = storage.key(i);
            if (key == null) continue;
            const value = String(storage.getItem(key) ?? '').slice(0,100000);
            total += value.length;
            if (total > 1500000) break;
            out[String(key).slice(0,300)] = value;
          }
        } catch (_) {}
        return out;
      };

      const capture = (force = false) => {
        if (!window.__htmlappStateCaptureEnabled || (!force && !dirty)) return;
        try {
          const fields = [];
          document.querySelectorAll('input,textarea,select,[contenteditable="true"]').forEach((el) => {
            if (fields.length >= 1000) return;
            const selector = selectorFor(el);
            if (!selector) return;
            let kind = 'value', value = '';
            if (el.matches('input[type=checkbox],input[type=radio]')) {
              kind = 'checked'; value = String(!!el.checked);
            } else if (el.isContentEditable) {
              kind = 'html'; value = String(el.innerHTML || '').slice(0,100000);
            } else {
              value = String(el.value ?? '').slice(0,100000);
            }
            fields.push({selector, kind, value});
          });
          const scrollRegions = [];
          document.querySelectorAll('*').forEach((el) => {
            if (scrollRegions.length >= 200) return;
            if (!el.scrollTop && !el.scrollLeft) return;
            const selector = selectorFor(el);
            if (selector) scrollRegions.push({
              selector, top: String(el.scrollTop || 0), left: String(el.scrollLeft || 0)
            });
          });

          const canvases = [];
          let canvasBytes = 0;
          document.querySelectorAll('canvas').forEach((canvas) => {
            if (canvases.length >= 8 || canvasBytes >= 1200000) return;
            const selector = selectorFor(canvas);
            if (!selector) return;
            try {
              const dataURL = canvas.toDataURL('image/png');
              if (dataURL.length <= 500000 && canvasBytes + dataURL.length <= 1200000) {
                canvasBytes += dataURL.length;
                canvases.push({selector, dataURL});
              }
            } catch (_) {}
          });

          const media = [];
          document.querySelectorAll('audio,video').forEach((el) => {
            if (media.length >= 20) return;
            const selector = selectorFor(el);
            if (!selector) return;
            media.push({
              selector,
              currentTime: String(Number(el.currentTime || 0)),
              volume: String(Number(el.volume ?? 1)),
              muted: String(!!el.muted),
              playbackRate: String(Number(el.playbackRate || 1))
            });
          });

          const html = document.documentElement?.outerHTML || '';
          if (new TextEncoder().encode(html).length > 3500000) return;
          window.webkit.messageHandlers.htmlappState.postMessage({
            html,
            scrollX: Number(scrollX || 0),
            scrollY: Number(scrollY || 0),
            fields,
            localStorage: storageObject(localStorage),
            sessionStorage: storageObject(sessionStorage),
            scrollRegions,
            canvases,
            media,
            focusedSelector: selectorFor(document.activeElement)
          });
          dirty = false;
        } catch (_) {}
      };

      setInterval(() => capture(false), 2000);
      addEventListener('pagehide', () => capture(true), {capture:true});
      document.addEventListener('visibilitychange', () => {
        if (document.visibilityState === 'hidden') capture(true);
      });
      window.__htmlappCaptureStateNow = () => capture(true);
    })();
    """#
}

struct HTMLAppOfflineManifestEntry: Codable {
    var originalURL: String
    var relativePath: String
    var contentType: String
    var savedAt: Date
    var byteCount: Int
}

struct HTMLAppOfflineManifest: Codable {
    var updatedAt: Date
    var entries: [String: HTMLAppOfflineManifestEntry]
}

final class HTMLAppOfflineCache {
    static let shared = HTMLAppOfflineCache()

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.mekabrine.htmlapp.offline-monitor")
    private let lock = NSLock()
    private var pathStatus: NWPath.Status = .requiresConnection
    private let ioQueue = DispatchQueue(label: "com.mekabrine.htmlapp.offline-cache", qos: .utility)

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.lock.lock()
            self?.pathStatus = path.status
            self?.lock.unlock()
        }
        monitor.start(queue: monitorQueue)
    }

    var isOffline: Bool {
        lock.lock(); defer { lock.unlock() }
        return pathStatus != .satisfied
    }

    private func root(appID: String) -> URL {
        SourceCache.shared.baseURL(appID: appID).appendingPathComponent("offline-cache", isDirectory: true)
    }

    private func manifestURL(appID: String) -> URL {
        root(appID: appID).appendingPathComponent("manifest.json")
    }

    func manifest(appID: String) -> HTMLAppOfflineManifest {
        guard let data = try? Data(contentsOf: manifestURL(appID: appID)),
              let value = try? JSONDecoder().decode(HTMLAppOfflineManifest.self, from: data) else {
            return HTMLAppOfflineManifest(updatedAt: .distantPast, entries: [:])
        }
        return value
    }

    func cachedRelativeURL(appID: String, originalURL: String) -> String? {
        manifest(appID: appID).entries[originalURL]?.relativePath
    }

    func rewriteHTMLForOffline(appID: String, html: String) -> (String, Int) {
        let entries = manifest(appID: appID).entries.values
        guard !entries.isEmpty else { return (html, 0) }
        var output = html
        var count = 0
        for entry in entries.sorted(by: { $0.originalURL.count > $1.originalURL.count }) {
            let original = entry.originalURL
            let local = entry.relativePath
            let forms = [
                ("src=\"" + original + "\"", "src=\"" + local + "\""),
                ("src='" + original + "'", "src='" + local + "'"),
                ("href=\"" + original + "\"", "href=\"" + local + "\""),
                ("href='" + original + "'", "href='" + local + "'"),
                ("poster=\"" + original + "\"", "poster=\"" + local + "\""),
                ("poster='" + original + "'", "poster='" + local + "'"),
                ("url(\"" + original + "\")", "url(\"" + local + "\")"),
                ("url('" + original + "')", "url('" + local + "')"),
                ("url(" + original + ")", "url(" + local + ")")
            ]
            var replaced = false
            for (from, to) in forms where output.contains(from) {
                output = output.replacingOccurrences(of: from, with: to)
                replaced = true
            }
            if replaced { count += 1 }
        }
        return (output, count)
    }

    func runtimeOfflineScript(appID: String) -> String {
        let pairs = manifest(appID: appID).entries.reduce(into: [String: String]()) {
            $0[$1.key] = $1.value.relativePath
        }
        guard !pairs.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: pairs),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return """
        (() => {
          const cache = \(json);
          const absolute = (value) => {
            try { return new URL(String(value), document.baseURI).href; }
            catch (_) { return String(value); }
          };
          const offline = () => !navigator.onLine;
          const cached = (value) => offline() ? (cache[absolute(value)] || null) : null;
          window.__htmlappOfflineExperimental = true;
          const originalFetch = window.fetch?.bind(window);
          if (originalFetch) {
            window.fetch = (input, init = {}) => {
              const method = String(init?.method || (input && input.method) || 'GET').toUpperCase();
              if (method === 'GET') {
                const value = typeof input === 'string' ? input : input?.url;
                const local = cached(value);
                if (local) return originalFetch(local, init);
              }
              return originalFetch(input, init);
            };
          }
          if (window.XMLHttpRequest) {
            const open = XMLHttpRequest.prototype.open;
            XMLHttpRequest.prototype.open = function(method, url, ...rest) {
              const local = String(method || 'GET').toUpperCase() === 'GET' ? cached(url) : null;
              return open.call(this, method, local || url, ...rest);
            };
          }
          const rewrite = (root = document) => {
            for (const el of root.querySelectorAll?.('[src],[href],[poster]') || []) {
              for (const attr of ['src','href','poster']) {
                const value = el.getAttribute?.(attr);
                const local = value && cached(value);
                if (local) el.setAttribute(attr, local);
              }
            }
          };
          document.addEventListener('DOMContentLoaded', () => { if (offline()) rewrite(document); }, {once:true});
          addEventListener('offline', () => {
            try { window.webkit.messageHandlers.htmlappOfflineCache.postMessage({offlineActivated:true}); } catch (_) {}
            rewrite(document);
          });
          const observer = new MutationObserver(records => {
            for (const record of records) for (const node of record.addedNodes) {
              if (node?.nodeType === 1) {
                rewrite(node);
                for (const attr of ['src','href','poster']) {
                  const value = node.getAttribute?.(attr);
                  const local = value && cached(value);
                  if (local) node.setAttribute(attr, local);
                }
              }
            }
          });
          const observe = () => {
            if (document.documentElement) {
              observer.observe(document.documentElement, {subtree:true, childList:true});
            } else {
              setTimeout(observe, 0);
            }
          };
          observe();
        })();
        """
    }

    func shouldRefreshOnOpen(appID: String) -> Bool {
        let key = "htmlapp.offline.openCount." + appID
        let count = UserDefaults.standard.integer(forKey: key) + 1
        UserDefaults.standard.set(count, forKey: key)
        return count % 3 == 0
    }

    func refreshFromHTML(appID: String, html: String) async {
        guard !isOffline else { return }
        let urls = Self.discoverURLs(in: html)
        await cache(appID: appID, urls: Array(urls.prefix(180)))
    }

    func cache(appID: String, urls: [String]) async {
        guard !isOffline else { return }
        let unique = Array(Set(urls)).prefix(180)
        for raw in unique {
            guard let url = URL(string: raw),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { continue }
            await cacheOne(appID: appID, url: url, depth: 0)
        }
    }

    private func cacheOne(appID: String, url: URL, depth: Int) async {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("HTMLApp/1.6 Offline Snapshot", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  data.count <= 15_000_000 else { return }
            let cacheControl = http.value(forHTTPHeaderField: "Cache-Control")?.lowercased() ?? ""
            guard !cacheControl.contains("no-store") else { return }
            let contentType = http.value(forHTTPHeaderField: "Content-Type")?.split(separator: ";").first.map(String.init)
                ?? "application/octet-stream"
            let ext = Self.fileExtension(url: url, contentType: contentType)
            let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
            let relative = "offline-cache/" + digest + (ext.isEmpty ? "" : "." + ext)
            let destination = SourceCache.shared.baseURL(appID: appID).appendingPathComponent(relative)

            var payload = data
            if depth < 2,
               (contentType == "text/css" || contentType.contains("javascript")),
               let text = String(data: data, encoding: .utf8) {
                let dependencies = Self.textDependencies(
                    in: text, baseURL: url, contentType: contentType)
                for dependency in dependencies.prefix(48) {
                    await cacheOne(appID: appID, url: dependency.absoluteURL, depth: depth + 1)
                }
                var rewritten = text
                let current = manifest(appID: appID)
                for dependency in dependencies.sorted(by: { $0.raw.count > $1.raw.count }) {
                    guard let cached = current.entries[dependency.absoluteURL.absoluteString] else { continue }
                    let localName = URL(fileURLWithPath: cached.relativePath).lastPathComponent
                    rewritten = rewritten.replacingOccurrences(of: dependency.raw, with: localName)
                }
                if let rewrittenData = rewritten.data(using: .utf8) {
                    payload = rewrittenData
                }
            }

            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try payload.write(to: destination, options: .atomic)

            ioQueue.sync {
                var current = manifest(appID: appID)
                current.updatedAt = Date()
                current.entries[url.absoluteString] = HTMLAppOfflineManifestEntry(
                    originalURL: url.absoluteString,
                    relativePath: relative,
                    contentType: contentType,
                    savedAt: Date(),
                    byteCount: payload.count
                )
                if let encoded = try? JSONEncoder().encode(current) {
                    try? FileManager.default.createDirectory(at: root(appID: appID), withIntermediateDirectories: true)
                    try? encoded.write(to: manifestURL(appID: appID), options: .atomic)
                }
            }
        } catch {
            // Experimental cache never interrupts the live online app.
        }
    }

    private static func discoverURLs(in html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "https?://[^\\s'\"<>\\\\)]+") else {
            return []
        }
        let source = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: source.length)).compactMap {
            let value = source.substring(with: $0.range)
            return value.count <= 2048 ? value : nil
        }
    }

    private struct TextDependency {
        var raw: String
        var absoluteURL: URL
    }

    private static func textDependencies(in text: String, baseURL: URL, contentType: String) -> [TextDependency] {
        let patterns: [String]
        if contentType == "text/css" {
            patterns = [#"url\(\s*['"]?([^'")\s]+)"#]
        } else {
            patterns = [
                #"(?:from\s*|import\s*\(\s*|import\s*)['"]([^'"]+)['"]"#
            ]
        }
        let source = text as NSString
        var seen = Set<String>()
        var result: [TextDependency] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
                guard match.numberOfRanges > 1 else { continue }
                let raw = source.substring(with: match.range(at: 1))
                guard !raw.hasPrefix("data:"), !raw.hasPrefix("blob:"), !raw.hasPrefix("#"),
                      let resolved = URL(string: raw, relativeTo: baseURL)?.absoluteURL,
                      ["http", "https"].contains(resolved.scheme?.lowercased() ?? ""),
                      seen.insert(resolved.absoluteString).inserted else { continue }
                result.append(TextDependency(raw: raw, absoluteURL: resolved))
            }
        }
        return result
    }

    private static func fileExtension(url: URL, contentType: String) -> String {
        if !url.pathExtension.isEmpty, url.pathExtension.count <= 8 {
            return url.pathExtension.lowercased()
        }
        switch contentType.lowercased() {
        case "text/css": return "css"
        case "text/javascript", "application/javascript": return "js"
        case "application/json": return "json"
        case "image/png": return "png"
        case "image/jpeg": return "jpg"
        case "image/webp": return "webp"
        case "image/svg+xml": return "svg"
        case "font/woff": return "woff"
        case "font/woff2": return "woff2"
        case "audio/mpeg": return "mp3"
        case "video/mp4": return "mp4"
        default: return "bin"
        }
    }
}

enum HTMLAppOfflineDiscoveryScript {
    static let source = #"""
    (() => {
      if (window.__htmlappOfflineDiscoveryInstalled) return;
      window.__htmlappOfflineDiscoveryInstalled = true;
      const seen = new Set();
      const flush = () => {
        if (!navigator.onLine) return;
        const batch = [];
        try {
          for (const entry of performance.getEntriesByType('resource')) {
            const url = String(entry.name || '');
            if (/^https?:\/\//i.test(url) && !seen.has(url)) {
              seen.add(url); batch.push(url);
              if (batch.length >= 40) break;
            }
          }
          if (batch.length) window.webkit.messageHandlers.htmlappOfflineCache.postMessage({urls: batch});
        } catch (_) {}
      };
      setInterval(flush, 12000);
      addEventListener('load', () => setTimeout(flush, 1500), {once:true});
    })();
    """#
}
