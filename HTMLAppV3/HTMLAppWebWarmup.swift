import UIKit
import WebKit

/// Primes the WKWebView process while the user is in the Library, so opening a
/// saved HTMLApp does not pay the entire first WebKit process startup cost.
@MainActor
enum HTMLAppWebWarmup {
    static let pool = WKProcessPool()
    private static var warming: WKWebView?
    private static var primed = false

    static func prime() {
        guard !primed, !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        primed = true
        let configuration = WKWebViewConfiguration()
        configuration.processPool = pool
        configuration.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: configuration)
        warming = view
        view.loadHTMLString("<!doctype html><html><body></body></html>", baseURL: nil)
    }

    static func release() {
        warming?.stopLoading()
        warming = nil
        primed = false
    }
}
