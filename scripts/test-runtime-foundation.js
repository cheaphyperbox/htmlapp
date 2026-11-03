#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const assert = require('node:assert/strict');

const source = fs.readFileSync(
  path.join(__dirname, '../HTMLAppV3/HTMLAppRuntimeFoundation.swift'), 'utf8'
).split('static let source = #"""')[1].split('"""#')[0];

async function main() {
  const events = new Map();
  const values = new Map();
  const records = new Map();
  const window = {
    HTMLAppNative: {
      appStorage: {
        get: async key => values.get(key),
        set: async (key, value) => { values.set(key, value); return { ok: true }; },
        remove: async key => { values.delete(key); return { ok: true }; }
      },
      db: {
        put: async (collection, id, document) => {
          records.set(collection + '/' + id, document); return { ok: true };
        },
        get: async (collection, id) => records.get(collection + '/' + id) || null,
        delete: async (collection, id) => records.delete(collection + '/' + id),
        query: async () => ({ items: [] }),
        search: async () => ({ items: [] }),
        count: async () => ({ count: records.size })
      }
    },
    addEventListener: (event, listener) => events.set(event, listener),
    removeEventListener: event => events.delete(event),
    dispatchEvent(event) { const listener = events.get(event.type); if (listener) listener(event); }
  };
  const document = { hidden: false, addEventListener() {} };
  vm.runInNewContext(source, { window, document, console, AbortController, Error, DOMException,
    Promise, CustomEvent: class CustomEvent { constructor(name, options) {
      this.type = name; this.detail = options?.detail;
    } } }, { filename: 'HTMLAppRuntimeFoundation.js' });

  const runtime = window.HTMLAppRuntime;
  const data = window.HTMLAppData;
  assert.ok(runtime && data);
  const successStates = [];
  assert.equal(await runtime.runOperation('save', async () => 42,
    state => successStates.push(state.status)), 42);
  assert.deepEqual(successStates, ['loading', 'success']);
  assert.equal(runtime.activeOperations.length, 0);

  const errorStates = [];
  await assert.rejects(runtime.runOperation('failure', async () => {
    throw new Error('failed');
  }, state => errorStates.push(state.status)), /failed/);
  assert.deepEqual(errorStates, ['loading', 'error']);

  const cancelStates = [];
  const stalled = runtime.runOperation('stalled', async () => new Promise(() => {}),
    state => cancelStates.push(state.status));
  assert.equal(runtime.cancelOperation('stalled'), true);
  await assert.rejects(stalled, error =>
    error.name === 'AbortError' && error.code === 'cancelled');
  assert.deepEqual(cancelStates, ['loading', 'cancelled']);
  assert.equal(runtime.activeOperations.length, 0);

  let runCount = 0;
  const first = runtime.runOperation('duplicate', async () => {
    runCount += 1; return 'single';
  });
  const second = runtime.runOperation('duplicate', async () => {
    runCount += 1; return 'unexpected';
  });
  assert.strictEqual(first, second);
  assert.equal(await first, 'single');
  assert.equal(runCount, 1);

  const collection = data.collection('workouts');
  await collection.put('w1', { duration: 10 });
  assert.equal((await collection.get('w1')).duration, 10);
  assert.throws(() => data.collection('../unsafe'), /Collection or migration key/);

  const migrated = [];
  const migrations = {
    1: async () => migrated.push(1),
    2: async () => migrated.push(2)
  };
  assert.equal(await data.migrate('workouts', 2, migrations), 2);
  assert.equal(await data.migrate('workouts', 2, migrations), 2);
  assert.deepEqual(migrated, [1, 2]);
  assert.equal(values.get('__htmlappSchema:workouts'), 2);

  let background = false;
  runtime.onBackground(() => { background = true; });
  events.get('pagehide')();
  assert.equal(background, true);
  console.log('Runtime foundation cancellation, data, migration and lifecycle checks passed.');
}

main().catch(error => { console.error(error); process.exitCode = 1; });
