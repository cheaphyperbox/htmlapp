const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const swift = fs.readFileSync('HTMLAppV3/NativeAPIBridge.swift', 'utf8');
const source = swift.split('static let source = #"""')[1].split('"""#')[0];
const messages = [], nodes = new Map();
const element = () => ({style:{},setAttribute(){},replaceChildren(){},append(...children){this.children=children},remove(){nodes.delete(this.id)}});
const document = {getElementById:id=>nodes.get(id),createElement:element,body:{appendChild:n=>nodes.set(n.id,n)},addEventListener(){}};
const listeners = new Map();
const window = {
  webkit:{messageHandlers:{htmlappNative:{postMessage:message=>messages.push(message)}}},
  addEventListener(type, handler) {
    const registered = listeners.get(type) || [];
    registered.push(handler);
    listeners.set(type, registered);
  },
  dispatchEvent(event) {
    for (const handler of listeners.get(event.type) || []) handler(event);
    return true;
  }
};
class CustomEvent {
  constructor(type, options = {}) {
    this.type = type;
    this.detail = options.detail;
  }
}
vm.runInNewContext(source, {window,document,CustomEvent,Map,Error,Date,Promise,console,navigator:{}});
(async () => {
  const result = window.HTMLAppNative.widgets.configure({id:'focus-streak',snapshot:{value:'7'}}).catch(e=>e);
  const first = messages.shift();
  assert.equal(first.method,'widgets.configure');
  window.__htmlappNativeResolve(first.id,false,{code:'app_group_unavailable',message:'Both profiles must authorize the group.'});
  const error = await result;
  assert.equal(error.code,'app_group_unavailable');
  assert.match(error.message,/Both profiles/);
  assert.match(nodes.get('__htmlappWidgetError').children[0].textContent,/app_group_unavailable/);
  const published = window.HTMLAppNative.widgets.configure({id:'focus-streak',snapshot:{value:'8'}});
  window.__htmlappNativeResolve(messages.shift().id,true,{published:true,reloadRequested:true,extensionVerified:false});
  assert.equal((await published).extensionVerified,false);
  assert.equal(nodes.size,0);
  const capabilityPromise = window.HTMLApp.capabilities();
  const capabilityCall = messages.shift();
  assert.equal(capabilityCall.method, 'capabilities.list');
  window.__htmlappNativeResolve(capabilityCall.id, true, {
    methods: ['device.torch','device.brightness'], permissions: ['camera','displayControl'], torchAvailable: true
  });
  assert.equal((await capabilityPromise).torchAvailable, true);
  const torchPromise = window.HTMLAppNative.device.torch(true);
  const torchCall = messages.shift();
  assert.equal(torchCall.method, 'device.torch');
  assert.equal(torchCall.args.enabled, true);
  window.__htmlappNativeResolve(torchCall.id, true, { enabled: true });
  assert.equal((await torchPromise).enabled, true);
  const brightnessPromise = window.HTMLAppNative.device.brightness(0.4);
  const brightnessCall = messages.shift();
  assert.equal(brightnessCall.method, 'device.brightness');
  assert.equal(brightnessCall.args.level, 0.4);
  window.__htmlappNativeResolve(brightnessCall.id, true, { level: 0.4 });
  assert.equal((await brightnessPromise).level, 0.4);
  const batteryPromise = window.HTMLAppNative.device.battery();
  const batteryCall = messages.shift();
  assert.equal(batteryCall.method, 'device.battery');
  window.__htmlappNativeResolve(batteryCall.id, true, {
    percentage: 78, charging: true, batteryState: 'charging', thermalState: 'nominal'
  });
  assert.equal((await batteryPromise).percentage, 78);
  window.htmlappLaunch = {source:'widget',widgetId:'focus-streak',
      actionId:'open-today',type:'route',route:'today'};
  const launch = await window.HTMLAppNative.launch.get();
  assert.equal(launch.route, 'today');
  assert.equal(await window.HTMLAppNative.launch.get(), null);
  let selectedTab = null;
  window.HTMLAppNative.tabs.onSelect(id => { selectedTab = id; });
  const tabs = window.HTMLAppNative.tabs.configure([
    {id:'home', title:'Home', symbol:'house.fill'},
    {id:'settings', title:'Settings', symbol:'gearshape.fill'}
  ]);
  const configureCall = messages.shift();
  assert.equal(configureCall.method, 'tabs.configure');
  assert.equal(configureCall.args.items.length, 2);
  window.__htmlappNativeResolve(configureCall.id, true, {enabled:true,count:2});
  assert.equal((await tabs).enabled, true);
  assert.equal(selectedTab, 'home', 'Native tabs must select their first destination');
  const ble = window.HTMLAppNative.bluetooth.scan(5);
  const bleCall = messages.shift();
  assert.equal(bleCall.method, 'bluetooth.scan');
  assert.equal(bleCall.args.seconds, 5);
  window.__htmlappNativeResolve(bleCall.id, true, {devices:[]});
  assert.equal((await ble).devices.length, 0);
  console.log('Widget bridge: rejection code/message, visible diagnostics, and publication states passed.');
})().catch(e=>{console.error(e);process.exitCode=1});
