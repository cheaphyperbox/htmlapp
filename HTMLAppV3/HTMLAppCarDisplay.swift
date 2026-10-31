import SwiftUI
import UIKit
import WebKit

/// Compatibility for tools that already launch the ordinary app on a car display.
/// This deliberately does not register an unsupported CPTemplateApplicationScene.
enum HTMLAppCarDisplay {
    static func updateScript(enabled: Bool) -> String {
        "window.__htmlappSetDisplay?.(\(enabled ? "true" : "false"));"
    }

    static let script = #"""
    (() => {
      let car = false;
      let last = '';
      const snapshot = () => Object.freeze({
        mode: car ? 'car' : 'standard',
        width: Math.round(window.visualViewport?.width ?? window.innerWidth),
        height: Math.round(window.visualViewport?.height ?? window.innerHeight)
      });
      Object.defineProperty(window, 'HTMLAppDisplay', {get: snapshot});
      const publish = () => {
        const root = document.documentElement;
        if (!root) return;
        const detail = snapshot();
        root.dataset.htmlappDisplay = detail.mode;
        root.style.setProperty('--htmlapp-viewport-height', detail.height + 'px');
        if (document.head && !document.getElementById('htmlapp-car-display')) {
          const style = document.createElement('style');
          style.id = 'htmlapp-car-display';
          style.textContent = `
            html[data-htmlapp-display="car"] { overflow-y:auto; }
            html[data-htmlapp-display="car"] body {
              min-width:0 !important; min-height:0; overflow-y:auto;
              overflow-wrap:break-word; -webkit-text-size-adjust:100%;
              padding-bottom:calc(var(--htmlapp-tabbar-height, 0px) + env(safe-area-inset-bottom, 0px) + 12px);
              box-sizing:border-box;
            }
            html[data-htmlapp-display="car"] :where(button, input, select, [role="button"]) {
              min-height:48px; font-size: max(16px, 1em);
            }
            html[data-htmlapp-display="car"] :where(img, video, canvas) { max-width:100%; }
          `;
          document.head.appendChild(style);
        }
        const key = JSON.stringify(detail);
        if (last !== key) {
          last = key;
          window.dispatchEvent(new CustomEvent('htmlapp:display-change', {detail}));
        }
      };
      window.__htmlappSetDisplay = enabled => { car = !!enabled; publish(); };
      window.addEventListener('resize', publish);
      window.visualViewport?.addEventListener('resize', publish);
      document.addEventListener('DOMContentLoaded', publish);
      publish();
    })();
    """#
}

/// Uses the WebView's own window, never a global "first connected scene".
final class HTMLAppDisplayWebView: WKWebView {
    private var lastDisplayKey = ""

    override func layoutSubviews() {
        super.layoutSubviews()
        updateDisplay()
    }

    func updateDisplay(force: Bool = false) {
        let enabled = UserDefaults.standard.bool(forKey: "htmlapp.carDisplay")
            || window?.traitCollection.userInterfaceIdiom == .carPlay
        let key = "\(enabled)-\(bounds.width)-\(bounds.height)"
        guard force || key != lastDisplayKey else { return }
        lastDisplayKey = key
        evaluateJavaScript(HTMLAppCarDisplay.updateScript(enabled: enabled), completionHandler: nil)
    }
}

struct HTMLAppCarWindowProbe: UIViewRepresentable {
    @Binding var isCarWindow: Bool

    final class Probe: UIView {
        var changed: ((Bool) -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); report() }
        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
            report()
        }
        private func report() {
            let value = window?.traitCollection.userInterfaceIdiom == .carPlay
            DispatchQueue.main.async { [weak self] in self?.changed?(value) }
        }
    }

    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.isUserInteractionEnabled = false
        view.changed = { isCarWindow = $0 }
        return view
    }
    func updateUIView(_ uiView: Probe, context: Context) {
        uiView.changed = { isCarWindow = $0 }
    }
}

struct HTMLAppDisplayRoot: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("htmlapp.carDisplay") private var forcedCarDisplay = false
    @State private var carWindow = false

    var body: some View {
        Group {
            if forcedCarDisplay || carWindow {
                VStack(spacing: 0) {
                    HStack {
                        Label("HTMLApp", systemImage: "car.fill").font(.headline)
                        Spacer()
                        if forcedCarDisplay && !carWindow {
                            Button { forcedCarDisplay = false } label: {
                                Text("Phone layout").frame(minHeight: 48)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 52)
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                            ForEach(store.apps.sorted {
                                if ($0.isFavorite == true) != ($1.isFavorite == true) {
                                    return $0.isFavorite == true
                                }
                                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                            }) { app in
                                Button { store.launch(app) } label: {
                                    Label(app.name, systemImage: app.isFavorite == true ? "star.fill" : "app")
                                        .font(.title3.weight(.semibold))
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(12)
                        if store.apps.isEmpty {
                            Text("Create or import apps on your phone while parked.")
                                .padding()
                        }
                        Text("Use interactive apps only while parked. This mode cannot detect vehicle motion.")
                            .font(.footnote).foregroundStyle(.secondary).padding(12)
                    }
                }
                .background(Color(uiColor: .systemBackground))
            } else {
                LibraryView()
            }
        }
        .background(HTMLAppCarWindowProbe(isCarWindow: $carWindow))
    }
}
