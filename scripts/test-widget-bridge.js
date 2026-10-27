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
// Use deterministic virtual timers: the native bridge needs browser timers,
// but tests must not wait for real 30-180 second deadlines.
const scheduled = new Map();
let nextTimer = 0;
const setTimeout = (callback, delay) => {
  const token = ++nextTimer;
  scheduled.set(token, {callback, delay});
  return token;
};
const clearTimeout = token => { scheduled.delete(token); };
vm.runInNewContext(source, {window,document,CustomEvent,Map,Error,Date,Promise,console,navigator:{},setTimeout,clearTimeout});
(async () => {
  // A lost native callback must reject with a consistent timeout code and
  // cleanup its pending timer. Late native callbacks must be harmless.
  const timeoutRequest = window.HTMLAppNative.device.battery().catch(e=>e);
  const timeoutCall = messages.shift();
  assert.equal(timeoutCall.method, 'device.battery');
  const timeoutTimer = [...scheduled.values()].find(item => item.delay === 30000);
  assert.ok(timeoutTimer, 'Normal native calls must have a finite timeout');
  timeoutTimer.callback();
  const timedOut = await timeoutRequest;
  assert.equal(timedOut.code, 'native_timeout');
  window.__htmlappNativeResolve(timeoutCall.id, true, {percentage: 1});
  assert.equal(scheduled.size, 0, 'Resolved or timed-out native requests must clear their timer');
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
  // The native UITabBar signals the initially selected tab after configuration.
  // Simulate that native-to-JavaScript callback in this bridge-only test.
  assert.equal(configureCall.args.selected, 'home');
  window.dispatchEvent(new CustomEvent('htmlapp:native-tab-select', {detail:{id:'home'}}));
  assert.equal(selectedTab, 'home', 'Native tabs must select their first destination');
  let selectedPerItem = null;
  const seven = window.HTMLAppNative.tabs.configure([
    {id:'one',title:'One',onSelect:()=>{selectedPerItem='one'}},
    {id:'two',title:'Two',onSelect:()=>{selectedPerItem='two'}},
    {id:'three',title:'Three'}, {id:'four',title:'Four'},
    {id:'five',title:'Five'}, {id:'six',title:'Six'},
    {id:'seven',title:'Seven',badge:'3'}
  ]);
  const sevenCall = messages.shift();
  assert.equal(sevenCall.args.items.length,7);
  assert.equal(sevenCall.args.items[0].onSelect,undefined);
  window.__htmlappNativeResolve(sevenCall.id,true,{enabled:true,count:7});
  await seven;
  window.dispatchEvent(new CustomEvent('htmlapp:native-tab-select',{detail:{id:'two'}}));
  assert.equal(selectedPerItem,'two');
  const updateTab = window.HTMLAppNative.tabs.update('seven',{badge:''});
  const updateCall = messages.shift();
  assert.equal(updateCall.method,'tabs.update');
  window.__htmlappNativeResolve(updateCall.id,true,{updated:true});
  await updateTab;
  const hideTab = window.HTMLAppNative.tabs.setHidden(true);
  const hideCall = messages.shift();
  assert.equal(hideCall.method,'tabs.setHidden');
  window.__htmlappNativeResolve(hideCall.id,true,{ok:true});
  await hideTab;
  const pulse = window.HTMLAppNative.tabs.pulse();
  const pulseCall = messages.shift();
  assert.equal(pulseCall.method,'tabs.pulse');
  window.__htmlappNativeResolve(pulseCall.id,true,{ok:true});
  await pulse;
  const push = window.HTMLAppNative.push.register();
  const pushCall = messages.shift();
  assert.equal(pushCall.method,'push.register');
  window.__htmlappNativeResolve(pushCall.id,true,{token:'test',appID:'fixture'});
  assert.equal((await push).appID,'fixture');
  const ble = window.HTMLAppNative.bluetooth.scan(5);
  const bleCall = messages.shift();
  assert.equal(bleCall.method, 'bluetooth.scan');
  assert.equal(bleCall.args.seconds, 5);
  window.__htmlappNativeResolve(bleCall.id, true, {devices:[]});
  assert.equal((await ble).devices.length, 0);
  assert.equal(scheduled.size, 0, 'No pending native request timers should remain after test completion');
  console.log('Widget bridge: request timeouts, callback cleanup, rejection diagnostics, and publication states passed.');
})().catch(e=>{console.error(e);process.exitCode=1});
