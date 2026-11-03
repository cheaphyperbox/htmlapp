#!/usr/bin/env node
'use strict';
const fs = require('fs');
const vm = require('vm');
const assert = require('node:assert/strict');
const path = require('path');

const root = path.resolve(__dirname, '..');
const native = fs.readFileSync(path.join(root, 'HTMLAppV3/NativeAPIBridge.swift'), 'utf8');
const editor = fs.readFileSync(path.join(root, 'HTMLAppV3/EditorWeb.swift'), 'utf8');

const nativeScript = native.split('enum HTMLNativeAPIScript {')[1]
  .split('static let source = #"""')[1].split('"""#')[0];
const viewportScript = editor.split('enum HTMLAppResponsiveViewport {')[1]
  .split('static let source = #"""')[1].split('"""#')[0];

async function testNativeRPC() {
  const sent = [];
  const listeners = new Map();
  const window = {
    addEventListener(name, cb) { listeners.set(name, cb); },
    webkit: { messageHandlers: { htmlappNative: {
      postMessage(message) {
        sent.push(message);
        if (message.method === 'network.request') return; // deliberately pending
        queueMicrotask(() => {
          window.__htmlappNativeResolve(message.id, true,
            message.method === 'capabilities.list'
              ? { methods: ['network.request', 'permissions.status'] }
              : { method: message.args?.method || '', hostPolicy: 'ask' });
        });
      }
    } } }
  };
  vm.runInNewContext(nativeScript, {
    window, setTimeout, clearTimeout, queueMicrotask, console,
    AbortController, DOMException, Response, Blob, atob
  }, { filename: 'HTMLNativeAPIScript.js' });
  const api = window.HTMLAppNative;
  assert.equal(api.protocolVersion, 2);
  assert.equal(await api.capabilities.has('network.request'), true);
  assert.equal(await api.capabilities.has('nonexistent.method'), false);
  assert.equal((await api.capabilities.describe('permissions.status')).method, 'permissions.status');
  assert.equal((await api.permissions.status('camera')).hostPolicy, 'ask');
  assert.equal(typeof api.audio.record, 'function');
  assert.equal(typeof api.video.capture, 'function');
  assert.equal(typeof api.ui.colorPicker, 'function');
  await api.audio.record({ maxDuration: 30 });
  await api.audio.levels();
  await api.audio.stopRecording();
  await api.video.capture({ maxDuration: 15 });
  await api.ui.colorPicker({ hex: '#445566' });
  assert.ok(sent.some(msg => msg.method === 'audio.record' && msg.args.maxDuration === 30));
  assert.ok(sent.some(msg => msg.method === 'audio.stopRecording'));
  assert.ok(sent.some(msg => msg.method === 'video.capture' && msg.args.maxDuration === 15));
  assert.ok(sent.some(msg => msg.method === 'ui.colorPicker'));

  const controller = new AbortController();
  const request = api.network.request({ url: 'https://example.org/data', signal: controller.signal });
  controller.abort();
  await assert.rejects(request, err => err.code === 'cancelled');
  assert.ok(sent.some(msg => msg.method === 'bridge.cancel' && msg.args.targetID));
  listeners.get('pagehide')();
}

function testViewport() {
  const elements = {};
  const head = { appendChild(node) {
    if (node.name === 'viewport') elements.viewport = node;
    if (node.id) elements[node.id] = node;
  } };
  const root = { style: { setProperty() {} } };
  const document = {
    documentElement: root, head,
    querySelector(selector) { return selector === 'meta[name="viewport"]' ? (elements.viewport || null) : null; },
    getElementById(id) { return elements[id] || null; },
    createElement(tag) { return { tag, name: '', id: '', content: '', textContent: '' }; }
  };
  let enforce;
  class MutationObserver {
    constructor(callback) { enforce = callback; }
    observe() {}
    disconnect() {}
  }
  vm.runInNewContext(viewportScript, {
    document, MutationObserver, window: { addEventListener() {} }
  }, { filename: 'HTMLAppResponsiveViewport.js' });
  assert.ok(elements.viewport.content.includes('user-scalable=no'));
  assert.ok(elements.viewport.content.includes('maximum-scale=1'));
  assert.ok(elements.__htmlappViewportGuard.textContent.includes('overflow-x:clip'));
  assert.ok(elements.__htmlappViewportGuard.textContent.includes('data-htmlapp-horizontal-scroll'));
  assert.ok(elements.__htmlappViewportGuard.textContent.includes('overflow-wrap:anywhere'));
  elements.viewport.content = 'width=640, user-scalable=yes';
  enforce();
  assert.ok(elements.viewport.content.includes('user-scalable=no'));
  elements.__htmlappViewportGuard.textContent = 'body{overflow-x:scroll}';
  enforce();
  assert.ok(elements.__htmlappViewportGuard.textContent.includes('overflow-x:clip'));
}

(async () => {
  await testNativeRPC();
  testViewport();
  console.log('Native bridge and app viewport JS tests passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
