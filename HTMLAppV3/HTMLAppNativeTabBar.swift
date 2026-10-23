import UIKit
import WebKit

/// A genuine UIKit tab bar with the platform's native material.
/// Full floating/sidebar behavior on iOS 26 needs a UITabBarController host.
/// Tabs are declarative: generated HTML controls content via the selection event.
@MainActor
final class HTMLAppNativeTabBar: NSObject, UITabBarControllerDelegate {
    struct Tab {
        let id: String
        let title: String
        let symbol: String
    }

    private weak var webView: WKWebView?
    private var controller: UITabBarController?
    private weak var parent: UIViewController?
    private var tabs: [Tab] = []
    private var mountAttempts = 0

    init(webView: WKWebView) {
        self.webView = webView
    }

    func configure(tabs: [Tab]) {
        guard let webView else { return }
        self.tabs = tabs
        let tabsController: UITabBarController
        if let controller { tabsController = controller }
        else {
            guard let root = webView.window?.rootViewController else {
                guard mountAttempts < 20 else { return }
                mountAttempts += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
                    guard let self, !self.tabs.isEmpty else { return }
                    self.configure(tabs: self.tabs)
                }
                return
            }
            mountAttempts = 0
            let host = Self.topController(from: root)
            let created = UITabBarController()
            created.delegate = self
            created.view.backgroundColor = .clear
            created.view.isOpaque = false
            // UIKit must own this bar to provide native iOS 26 Liquid Glass.
            host.addChild(created)
            host.view.addSubview(created.view)
            created.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                created.view.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
                created.view.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
                created.view.heightAnchor.constraint(equalToConstant: 84),
                created.view.bottomAnchor.constraint(equalTo: host.view.safeAreaLayoutGuide.bottomAnchor)
            ])
            created.didMove(toParent: host)
            parent = host
            controller = created
            tabsController = created
        }
        tabsController.viewControllers = tabs.map { item in
            let vc = UIViewController()
            vc.view.backgroundColor = .clear
            vc.view.isUserInteractionEnabled = false
            vc.tabBarItem = UITabBarItem(title: item.title, image: UIImage(systemName: item.symbol), tag: 0)
            return vc
        }
        tabsController.selectedIndex = 0
        tabsController.tabBar.isHidden = false
        if let first = tabs.first { signal(first.id) }
    }

    func select(id: String) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == id }), let controller else { return false }
        controller.selectedIndex = index
        signal(id)
        return true
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        let index = tabBarController.selectedIndex
        if tabs.indices.contains(index) { signal(tabs[index].id) }
    }

    private static func topController(from root: UIViewController) -> UIViewController {
        if let presented = root.presentedViewController { return topController(from: presented) }
        if let navigation = root as? UINavigationController {
            return topController(from: navigation.visibleViewController ?? navigation)
        }
        return root
    }

    private func signal(_ id: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: ["id": id]),
              let json = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.dispatchEvent(new CustomEvent('htmlapp:native-tab-select', { detail: \(json) }));")
    }

    func remove() {
        if let controller {
            controller.willMove(toParent: nil)
            controller.view.removeFromSuperview()
            controller.removeFromParent()
        }
        controller = nil
        parent = nil
        tabs = []
        mountAttempts = 0
    }
}
