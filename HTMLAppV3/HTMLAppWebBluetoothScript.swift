import Foundation

/// Web Bluetooth discovery compatibility for generated apps inside HTMLApp.
/// It deliberately does not pretend to implement BLE GATT or Classic Bluetooth.
enum HTMLAppWebBluetoothScript {
    static let source = #"""
    (() => {
      'use strict';
      if (navigator.bluetooth && typeof navigator.bluetooth.requestDevice === 'function') return;
      function exception(message, name) {
        try { return new DOMException(message, name); }
        catch (_) { const e = new Error(message); e.name = name; return e; }
      }
      const api = {
        async requestDevice(options = {}) {
          if (!options.acceptAllDevices && !(Array.isArray(options.filters) && options.filters.length)) {
            throw new TypeError('Provide acceptAllDevices: true or a non-empty filters array.');
          }
          if (!window.HTMLAppNative?.bluetooth?.scan) {
            throw exception('Native Bluetooth discovery is not available in this HTMLApp environment.', 'NotSupportedError');
          }
          const result = await window.HTMLAppNative.bluetooth.scan(6);
          let devices = Array.isArray(result?.devices) ? result.devices : [];
          if (!options.acceptAllDevices && options.filters?.length) {
            devices = devices.filter(device => options.filters.some(filter =>
              (!filter.name || device.name === filter.name) &&
              (!filter.namePrefix || device.name?.startsWith(filter.namePrefix)) &&
              !filter.services && !filter.manufacturerData && !filter.serviceData
            ));
          }
          if (!devices.length) throw exception('No nearby advertising Bluetooth LE devices found.', 'NotFoundError');
          const selection = await new Promise((resolve, reject) => {
            const shade = document.createElement('div');
            shade.setAttribute('role', 'presentation');
            shade.style.cssText = 'position:fixed;inset:0;z-index:2147483647;display:flex;align-items:center;justify-content:center;background:rgba(0,0,0,.68);padding:20px;font-family:-apple-system,system-ui,sans-serif;';
            const panel = document.createElement('section');
            panel.setAttribute('role', 'dialog');
            panel.setAttribute('aria-modal', 'true');
            panel.setAttribute('aria-label', 'Choose a Bluetooth device');
            panel.style.cssText = 'color:#111;background:#fff;border-radius:18px;padding:18px;width:min(100%,420px);max-height:80vh;overflow:auto;box-sizing:border-box;';
            const title = document.createElement('h2');
            title.textContent = 'Nearby Bluetooth devices';
            title.style.cssText = 'font-size:19px;margin:0 0 8px;color:#111;';
            const detail = document.createElement('p');
            detail.textContent = 'Choose a Bluetooth Low Energy device discovered by your iPhone.';
            detail.style.cssText = 'font-size:13px;color:#555;margin:0 0 12px;';
            panel.append(title,detail);
            function finish(device, error) {
              shade.remove();
              if (error) reject(error); else resolve(device);
            }
            devices.forEach(device => {
              const button = document.createElement('button');
              button.type = 'button';
              button.textContent = (device.name || 'Unnamed device') + '  •  ' + (device.rssi ?? '?') + ' dBm';
              button.style.cssText = 'display:block;width:100%;padding:12px;text-align:left;margin:6px 0;border:1px solid #ddd;border-radius:10px;background:#f6f6f8;color:#111;font-size:15px;min-height:44px;';
              button.onclick = () => finish(device);
              panel.append(button);
            });
            const cancel = document.createElement('button');
            cancel.type = 'button';
            cancel.textContent = 'Cancel';
            cancel.style.cssText = 'width:100%;margin-top:10px;padding:12px;border:0;border-radius:10px;background:#eee;color:#111;min-height:44px;';
            cancel.onclick = () => finish(null, exception('User cancelled Bluetooth selection.', 'NotFoundError'));
            panel.append(cancel);
            shade.append(panel);
            (document.body || document.documentElement).append(shade);
            cancel.focus();
          });
          return {
            id: String(selection.id || ''),
            name: selection.name || null,
            gatt: {
              connected: false,
              connect: async () => { throw exception('BLE GATT connections are not supported by this HTMLApp compatibility chooser.', 'NotSupportedError'); },
              disconnect: () => {}
            },
            forget: async () => {}
          };
        },
        async getAvailability() {
          return !!window.HTMLAppNative?.bluetooth?.scan;
        },
        async getDevices() { return []; }
      };
      try { Object.defineProperty(navigator, 'bluetooth', { configurable: true, value: api }); }
      catch (_) { /* A native browser implementation may be read-only. */ }
    })();
    """#
}
