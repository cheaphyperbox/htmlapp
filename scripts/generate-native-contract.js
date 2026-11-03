#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const registry = fs.readFileSync(path.join(root, 'HTMLAppV3/HTMLAppBridgeRegistry.swift'), 'utf8');
const section = registry.split('static let methods: [String] = [')[1].split('static let methodSet')[0];
const methods = [...section.matchAll(/"([A-Za-z][A-Za-z0-9]*\.[A-Za-z][A-Za-z0-9]*)"/g)]
  .map(match => match[1]).sort();
if (methods.length < 120 || new Set(methods).size !== methods.length)
  throw new Error('Invalid registry method list');
const trailer = JSON.parse(fs.readFileSync(path.join(root, 'scripts/native-contract-types.json'), 'utf8'));
const ts = '// GENERATED from HTMLAppBridgeRegistry.swift — do not edit manually.\n' +
  'export type HTMLAppNativeMethod =\n' +
  methods.map((method, index) => "  | '" + method + "'" + (index === methods.length - 1 ? ';' : '')).join('\n') +
  '\n' + trailer.join('\n');
const json = JSON.stringify({
  schemaVersion: 1,
  protocolVersion: 2,
  description: 'Registered host methods are not necessarily available on every device or provisioned build.',
  methods
}, null, 2) + '\n';
for (const [filename, text] of [
  ['docs/htmlapp-native-api.d.ts', ts],
  ['docs/htmlapp-native-api.json', json]
]) {
  const destination = path.join(root, filename);
  if (process.argv.includes('--check')) {
    if (!fs.existsSync(destination) || fs.readFileSync(destination, 'utf8') !== text)
      throw new Error(filename + ' is stale; run node scripts/generate-native-contract.js');
  } else {
    fs.mkdirSync(path.dirname(destination), { recursive: true });
    fs.writeFileSync(destination, text);
  }
}
console.log('Native contracts synced with ' + methods.length + ' supported methods.');
