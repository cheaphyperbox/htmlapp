import Foundation

/// Small, optional, forward-compatible JavaScript helpers for saved HTMLApps.
/// This does not grant new native permissions or keep JavaScript alive while
/// iOS suspends the WebView.
enum HTMLAppRuntimeFoundation {
    static let source = #"""
    (() => {
      if (window.HTMLAppRuntime || window.HTMLAppData) return;

      const nativeAPI = group => {
        const api = window.HTMLAppNative?.[group];
        if (!api) throw Object.assign(new Error('This HTMLApp feature is unavailable.'), { code: 'bridge_unavailable' });
        return api;
      };
      const validName = name => {
        if (typeof name !== 'string' || !/^[A-Za-z0-9_-]{1,80}$/.test(name))
          throw new TypeError('Collection or migration key must use 1–80 letters, digits, - or _.');
        return name;
      };
      const collection = name => {
        validName(name);
        return Object.freeze({
          put: (id, document) => nativeAPI('db').put(name, id, document),
          get: id => nativeAPI('db').get(name, id),
          remove: id => nativeAPI('db').delete(name, id),
          query: (options = {}) => nativeAPI('db').query(name, options),
          search: (text, limit = 50) => nativeAPI('db').search(name, text, limit),
          count: () => nativeAPI('db').count(name)
        });
      };
      const kv = Object.freeze({
        get: key => nativeAPI('appStorage').get(key),
        set: (key, value) => nativeAPI('appStorage').set(key, value),
        remove: key => nativeAPI('appStorage').remove(key)
      });
      const data = Object.freeze({
        collection,
        kv,
        migrate: async (name, targetVersion, migrations) => {
          validName(name);
          if (!Number.isInteger(targetVersion) || targetVersion < 0 || targetVersion > 1000)
            throw new RangeError('Invalid schema version.');
          const key = '__htmlappSchema:' + name;
          let current = Number(await kv.get(key) || 0);
          if (!Number.isInteger(current) || current < 0) throw new Error('Invalid saved schema version.');
          if (current > targetVersion) throw new Error('The app data belongs to a newer schema.');
          while (current < targetVersion) {
            const next = current + 1;
            const migrate = migrations?.[next];
            if (typeof migrate !== 'function')
              throw new Error('Missing migration for schema version ' + next);
            // Migrations must be idempotent; a kill between data writes and
            // the marker update can legitimately retry a step on next launch.
            await migrate({ from: current, to: next, collection, kv });
            await kv.set(key, next);
            current = next;
          }
          return current;
        }
      });

      const operations = new Map();
      const report = (onChange, state) => {
        if (typeof onChange === 'function') {
          try { onChange(state); } catch (error) { console.warn('HTMLApp operation status callback failed', error); }
        }
      };
      const runOperation = (name, work, onChange) => {
        validName(name);
        if (typeof work !== 'function') throw new TypeError('Provide a task function.');
        if (operations.has(name)) return operations.get(name).promise;
        const controller = new AbortController();
        report(onChange, { status: 'loading', name });
        const promise = Promise.resolve()
          .then(() => work({ signal: controller.signal }))
          .then(value => {
            if (controller.signal.aborted) throw new DOMException('Cancelled', 'AbortError');
            report(onChange, { status: 'success', name });
            return value;
          }, error => {
            report(onChange, {
              status: controller.signal.aborted ? 'cancelled' : 'error',
              name, error
            });
            throw error;
          })
          .finally(() => operations.delete(name));
        operations.set(name, { controller, promise });
        return promise;
      };
      const cancelOperation = name => {
        const entry = operations.get(name);
        if (!entry) return false;
        entry.controller.abort();
        return true;
      };

      const onLifecycle = (state, callback) => {
        if (typeof callback !== 'function') throw new TypeError('Provide an event handler.');
        const handler = event => {
          if (event.detail?.state === state) callback(event.detail);
        };
        window.addEventListener('htmlapp:lifecycle', handler);
        return () => window.removeEventListener('htmlapp:lifecycle', handler);
      };
      const publishLifecycle = state => {
        window.dispatchEvent(new CustomEvent('htmlapp:lifecycle', { detail: { state } }));
      };
      document.addEventListener('visibilitychange', () => {
        publishLifecycle(document.hidden ? 'inactive' : 'active');
      });
      window.addEventListener('pagehide', () => {
        for (const item of operations.values()) item.controller.abort();
        publishLifecycle('background');
      });
      window.addEventListener('pageshow', () => publishLifecycle('resume'));

      const runtime = Object.freeze({
        runOperation, cancelOperation,
        get activeOperations() { return Array.from(operations.keys()); },
        get isVisible() { return !document.hidden; },
        onActive: cb => onLifecycle('active', cb),
        onInactive: cb => onLifecycle('inactive', cb),
        onBackground: cb => onLifecycle('background', cb),
        onResume: cb => onLifecycle('resume', cb)
      });
      Object.defineProperty(window, 'HTMLAppData', {
        configurable: false, enumerable: true, value: data
      });
      Object.defineProperty(window, 'HTMLAppRuntime', {
        configurable: false, enumerable: true, value: runtime
      });
    })();
    """#
}
