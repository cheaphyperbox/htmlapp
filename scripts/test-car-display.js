#!/usr/bin/env node
// Exercise the shipped document-start script across load, mode and viewport changes.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('HTMLAppV3/HTMLAppCarDisplay.swift', 'utf8');
const script = source.match(/static let script = #"""\n([\s\S]*?)\n    """#/)[1];

function page(withRoot = true) {
  const events = [];
  const windowListeners = {};
  const documentListeners = {};
  const viewportListeners = {};
  const styles = [];
  const properties = {};
  const root = {dataset: {}, style: {setProperty: (key, value) => { properties[key] = value; }}};
  const document = {
    documentElement: withRoot ? root : null,
    head: withRoot ? {appendChild: element => styles.push(element)} : null,
    getElementById: id => styles.find(element => element.id === id),
    createElement: () => ({}),
    addEventListener: (name, callback) => { documentListeners[name] = callback; }
  };
  const window = {
    innerWidth: 800, innerHeight: 480,
    visualViewport: {width: 800, height: 480,
      addEventListener: (name, callback) => { viewportListeners[name] = callback; }},
    addEventListener: (name, callback) => { windowListeners[name] = callback; },
    dispatchEvent: event => events.push(event)
  };
  vm.runInNewContext(script, {window, document,
    CustomEvent: class { constructor(type, options) { this.type = type; this.detail = options.detail; } }});
  return {window, document, root, events, properties, styles, windowListeners, documentListeners, viewportListeners};
}

const p = page();
assert.equal(p.window.HTMLAppDisplay.mode, 'standard');
assert.equal(p.root.dataset.htmlappDisplay, 'standard');
assert.ok(Object.isFrozen(p.window.HTMLAppDisplay));
p.window.__htmlappSetDisplay(true);
assert.equal(p.window.HTMLAppDisplay.mode, 'car');
assert.equal(p.root.dataset.htmlappDisplay, 'car');
assert.equal(p.properties['--htmlapp-viewport-height'], '480px');
assert.equal(p.styles.length, 1);
assert.ok(p.styles[0].textContent.includes('min-height:48px'));
assert.ok(p.styles[0].textContent.includes('--htmlapp-tabbar-height'));
let count = p.events.length;
p.window.__htmlappSetDisplay(true);
assert.equal(p.events.length, count, 'Unchanged layout must not repeatedly notify apps');
p.window.visualViewport.height = 250;
p.viewportListeners.resize();
assert.equal(p.window.HTMLAppDisplay.height, 250, 'Keyboard and short viewport resize must be visible');
assert.equal(p.properties['--htmlapp-viewport-height'], '250px');
assert.equal(p.events.at(-1).type, 'htmlapp:display-change');
assert.equal(p.events.at(-1).detail.height, 250);
p.window.__htmlappSetDisplay(false);
assert.equal(p.root.dataset.htmlappDisplay, 'standard', 'Returning to phone layout restores normal styling');
assert.equal(p.styles.length, 1, 'Mode changes must not duplicate styles');
p.window.visualViewport = null;
p.window.innerWidth = 640;
p.window.innerHeight = 360;
p.windowListeners.resize();
assert.equal(p.window.HTMLAppDisplay.width, 640);
assert.equal(p.window.HTMLAppDisplay.height, 360);
const early = page(false);
early.window.__htmlappSetDisplay(true);
early.document.documentElement = early.root;
early.document.head = {appendChild: element => early.styles.push(element)};
early.documentListeners.DOMContentLoaded();
assert.equal(early.root.dataset.htmlappDisplay, 'car', 'Mode set before HTML parsing must survive document readiness');
assert.equal(early.styles.length, 1);
const reloaded = page();
assert.equal(reloaded.window.HTMLAppDisplay.mode, 'standard', 'A new document does not inherit stale page state');
reloaded.window.__htmlappSetDisplay(true);
assert.equal(reloaded.root.dataset.htmlappDisplay, 'car', 'Native didFinish can restore mode after navigation');
console.log('Car display: startup, early DOM, mode changes, resize, keyboard, fallback viewport, event coalescing and reload passed.');
