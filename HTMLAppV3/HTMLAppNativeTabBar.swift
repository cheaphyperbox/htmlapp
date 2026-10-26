import UIKit
import WebKit

/// Native bottom navigation shown only when an installed HTML app opts in.
@MainActor
final class HTMLAppNativeTabBar: NSObject, UITabBarDelegate {
    struct Tab {
        let id: String
        let title: String
        let symbol: String
        let badge: String?
    }

    private weak var webView: WKWebView?
    private var bar: UITabBar?
    private var tabs: [Tab] = []
    private var mountAttempts = 0
    private var hidden = false

    init(webView: WKWebView) { self.webView = webView }

    func configure(tabs newTabs: [Tab], selected: String? = nil) {
        guard let webView else { return }
        tabs = newTabs
        let tabBar: UITabBar
        if let bar { tabBar = bar }
        else {
            guard let host = webView.window?.rootViewController?.view else {
                guard mountAttempts < 20 else { return }
                mountAttempts += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
                    guard let self, !self.tabs.isEmpty else { return }
                    self.configure(tabs: self.tabs, selected: selected)
                }
                return
            }
            mountAttempts = 0
            let created = UITabBar()
            created.delegate = self
            created.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(created)
            NSLayoutConstraint.activate([
                created.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                created.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                created.bottomAnchor.constraint(equalTo: host.safeAreaLayoutGuide.bottomAnchor)
            ])
            bar = created
            tabBar = created
            created.alpha = 0
            created.transform = CGAffineTransform(translationX: 0, y: 80)
            UIView.animate(withDuration: 0.35) {
                created.alpha = 1
                created.transform = .identity
            }
        }
        let items = newTabs.enumerated().map { index, tab -> UITabBarItem in
            let result = UITabBarItem(title: tab.title,
                                      image: UIImage(systemName: tab.symbol),
                                      tag: index)
            result.badgeValue = tab.badge?.isEmpty == false ? tab.badge : nil
            return result
        }
        tabBar.setItems(items, animated: true)
        let index = selected.flatMap { id in tabs.firstIndex(where: { $0.id == id }) } ?? 0
        tabBar.selectedItem = items.indices.contains(index) ? items[index] : nil
        if tabs.indices.contains(index) { signal(tabs[index].id) }
        reportInset()
    }

    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        guard tabs.indices.contains(item.tag) else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        signal(tabs[item.tag].id)
    }

    func select(id: String) -> Bool {
        guard let bar, let index = tabs.firstIndex(where: { $0.id == id }),
              let items = bar.items, items.indices.contains(index) else { return false }
        bar.selectedItem = items[index]
        signal(id)
        return true
    }

    func update(id: String, badge: String?, title: String?, symbol: String?) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == id }),
              let item = bar?.items?[index] else { return false }
        if let badge { item.badgeValue = badge.isEmpty ? nil : badge }
        if let title { item.title = title }
        if let symbol { item.image = UIImage(systemName: symbol) }
        return true
    }

    func setHidden(_ isHidden: Bool, animated: Bool) {
        guard let bar else { return }
        hidden = isHidden
        let update = {
            bar.alpha = isHidden ? 0 : 1
            bar.isUserInteractionEnabled = !isHidden
            bar.transform = isHidden
                ? CGAffineTransform(translationX: 0, y: 90) : .identity
        }
        if animated { UIView.animate(withDuration: 0.3, animations: update) }
        else { update() }
        reportInset()
    }

    func pulse() {
        guard let bar, !hidden else { return }
        UIView.animate(withDuration: 0.12, animations: {
            bar.transform = CGAffineTransform(scaleX: 1.025, y: 1.025)
        }) { _ in
            UIView.animate(withDuration: 0.25) { bar.transform = .identity }
        }
    }

    func remove() {
        bar?.removeFromSuperview()
        bar = nil
        tabs = []
        mountAttempts = 0
        hidden = false
        reportInset()
    }

    private func reportInset() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let height = self.hidden ? 0 : Int((self.bar?.intrinsicContentSize.height ?? 0)
                + (self.bar?.superview?.safeAreaInsets.bottom ?? 0))
            self.webView?.evaluateJavaScript("""
            document.documentElement.style.setProperty('--htmlapp-tabbar-height','\(height)px');
            window.dispatchEvent(new CustomEvent('htmlapp:tabbar-resize',{detail:{height:\(height)}}));
            """)
        }
    }

    private func signal(_ id: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: ["id": id]),
              let json = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.dispatchEvent(new CustomEvent('htmlapp:native-tab-select',{detail:\(json)}));")
    }
}
