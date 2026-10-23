import UIKit
import WebKit

/// A genuine UIKit tab bar with the platform's native material.
/// Full floating/sidebar behavior on iOS 26 needs a UITabBarController host.
/// Tabs are declarative: generated HTML controls content via the selection event.
@MainActor
final class HTMLAppNativeTabBar: NSObject, UITabBarDelegate {
    struct Tab {
        let id: String
        let title: String
        let symbol: String
    }

    private weak var webView: WKWebView?
    private var bar: UITabBar?
    private var tabs: [Tab] = []

    init(webView: WKWebView) {
        self.webView = webView
    }

    func configure(tabs: [Tab]) {
        guard let webView else { return }
        self.tabs = tabs
        let tabBar: UITabBar
        if let bar { tabBar = bar }
        else {
            tabBar = UITabBar()
            tabBar.delegate = self
            tabBar.translatesAutoresizingMaskIntoConstraints = false
            // Keep UIKit's own material/background for modern OS styling.
            webView.addSubview(tabBar)
            NSLayoutConstraint.activate([
                tabBar.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
                tabBar.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
                tabBar.bottomAnchor.constraint(equalTo: webView.safeAreaLayoutGuide.bottomAnchor)
            ])
            self.bar = tabBar
        }
        tabBar.items = tabs.enumerated().map { i, item in
            UITabBarItem(title: item.title, image: UIImage(systemName: item.symbol), tag: i)
        }
        tabBar.selectedItem = tabBar.items?.first
        webView.scrollView.contentInset.bottom = max(webView.scrollView.contentInset.bottom, tabBar.intrinsicContentSize.height)
        if let selected = tabs.first { signal(selected.id) }
    }

    func select(id: String) -> Bool {
        guard let i = tabs.firstIndex(where: { $0.id == id }),
              let item = bar?.items?[i] else { return false }
        bar?.selectedItem = item
        signal(id)
        return true
    }

    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        guard tabs.indices.contains(item.tag) else { return }
        signal(tabs[item.tag].id)
    }

    private func signal(_ id: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: ["id": id]),
              let json = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.dispatchEvent(new CustomEvent('htmlapp:native-tab-select', { detail: \(json) }));")
    }

    func remove() {
        bar?.removeFromSuperview()
        bar = nil
        tabs = []
        webView?.scrollView.contentInset.bottom = 0
    }

    deinit {
        // The owned UIKit subview is removed when its WKWebView is destroyed.
    }
}
