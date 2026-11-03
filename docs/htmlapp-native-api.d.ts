// GENERATED from HTMLAppBridgeRegistry.swift — do not edit manually.
export type HTMLAppNativeMethod =
  | 'ai.available'
  | 'ai.cancel'
  | 'ai.classify'
  | 'ai.complete'
  | 'ai.localAvailable'
  | 'ai.localComplete'
  | 'appStorage.all'
  | 'appStorage.clear'
  | 'appStorage.get'
  | 'appStorage.remove'
  | 'appStorage.set'
  | 'background.configure'
  | 'background.list'
  | 'background.refreshNow'
  | 'background.remove'
  | 'biometrics.authenticate'
  | 'bluetooth.battery'
  | 'bluetooth.gattRead'
  | 'bluetooth.gattStop'
  | 'bluetooth.gattSubscribe'
  | 'bluetooth.gattWrite'
  | 'bluetooth.scan'
  | 'bridge.cancel'
  | 'calendar.createEvent'
  | 'calendar.deleteEvent'
  | 'calendar.events'
  | 'calendar.updateEvent'
  | 'camera.capturePhoto'
  | 'capabilities.describe'
  | 'capabilities.list'
  | 'clipboard.readText'
  | 'clipboard.writeText'
  | 'contacts.create'
  | 'contacts.list'
  | 'contacts.pick'
  | 'db.count'
  | 'db.delete'
  | 'db.export'
  | 'db.get'
  | 'db.import'
  | 'db.put'
  | 'db.query'
  | 'db.search'
  | 'device.battery'
  | 'device.brightness'
  | 'device.info'
  | 'device.keepAwake'
  | 'device.torch'
  | 'documents.scan'
  | 'drawing.open'
  | 'externalApps.maps'
  | 'externalApps.shortcuts'
  | 'files.pick'
  | 'gamepad.list'
  | 'gamepad.start'
  | 'gamepad.stop'
  | 'haptics.pattern'
  | 'haptics.play'
  | 'health.available'
  | 'health.range'
  | 'health.today'
  | 'image.filter'
  | 'language.detect'
  | 'language.entities'
  | 'language.sentiment'
  | 'language.tokenize'
  | 'liveActivities.end'
  | 'liveActivities.list'
  | 'liveActivities.start'
  | 'liveActivities.update'
  | 'location.reverseGeocode'
  | 'location.roadSpeedLimit'
  | 'map.show'
  | 'motion.altitude'
  | 'motion.pedometer'
  | 'network.allowedDomains'
  | 'network.request'
  | 'network.revokeDomain'
  | 'nfc.available'
  | 'nfc.readNDEF'
  | 'nfc.writeText'
  | 'notifications.cancel'
  | 'notifications.installSound'
  | 'notifications.schedule'
  | 'pdf.inspect'
  | 'permissions.openSettings'
  | 'permissions.request'
  | 'permissions.status'
  | 'photos.pick'
  | 'photos.read'
  | 'photos.save'
  | 'push.register'
  | 'reminders.create'
  | 'reminders.delete'
  | 'reminders.list'
  | 'reminders.update'
  | 'secureStorage.get'
  | 'secureStorage.remove'
  | 'secureStorage.set'
  | 'share.present'
  | 'shortcuts.consumeAction'
  | 'speech.listen'
  | 'speech.listenStop'
  | 'speech.recognize'
  | 'speech.speak'
  | 'speech.stop'
  | 'speech.stopRecognizing'
  | 'spotlight.clear'
  | 'spotlight.enable'
  | 'spotlight.index'
  | 'spotlight.remove'
  | 'symbols.render'
  | 'symbols.search'
  | 'system.open'
  | 'tabs.configure'
  | 'tabs.pulse'
  | 'tabs.remove'
  | 'tabs.select'
  | 'tabs.setHidden'
  | 'tabs.update'
  | 'ui.alert'
  | 'ui.datePicker'
  | 'ui.menu'
  | 'vision.classifyImage'
  | 'vision.detectFaces'
  | 'vision.recognizeText'
  | 'vision.scanCodes'
  | 'widgets.configure'
  | 'widgets.list'
  | 'widgets.reload'
  | 'widgets.remove';

export interface HTMLAppNativeCapabilitySnapshot {
  protocolVersion: number;
  descriptorVersion: number;
  methods: HTMLAppNativeMethod[];
  permissions: string[];
  torchAvailable?: boolean;
  liveActivitiesAvailable?: boolean;
}

export interface HTMLAppNativeCapabilityDescriptor {
  method: HTMLAppNativeMethod;
  protocolVersion: number;
  available: boolean;
  permission: string;
  title: string;
  description: string;
  usage: string;
  constraints: string;
  minimumIOS: string;
  cancellable: boolean;
}

export interface HTMLAppNativeAPI {
  readonly protocolVersion: number;
  call<T = unknown>(method: HTMLAppNativeMethod, args?: Record<string, unknown>, options?: { signal?: AbortSignal }): Promise<T>;
  capabilities: (() => Promise<HTMLAppNativeCapabilitySnapshot>) & {
    list(): Promise<HTMLAppNativeCapabilitySnapshot>;
    has(method: HTMLAppNativeMethod): Promise<boolean>;
    describe(method: HTMLAppNativeMethod): Promise<HTMLAppNativeCapabilityDescriptor>;
  };
  permissions: {
    status(permission: string): Promise<{ hostPolicy: "ask" | "allow" | "deny"; systemAuthorization: string; canRequest: boolean }>;
    request(permission: string): Promise<{ hostAllowed: boolean }>;
    openSettings(): Promise<{ opened: boolean }>;
  };
  network: {
    request(args: { url: string; method?: "GET" | "POST" | "PUT" | "PATCH" | "DELETE" | "HEAD"; headers?: Record<string, string>; body?: string; signal?: AbortSignal }): Promise<{ status: number; ok: boolean; body: string; contentType: string }>;
    allowedDomains(): Promise<{ domains: string[] }>;
    revokeDomain(host: string): Promise<{ revoked: boolean }>;
  };
  ui: {
    alert(args: { title?: string; message?: string; actions?: { id: string; title: string; style?: "cancel" | "default" | "destructive" }[] }): Promise<{ id?: string; index?: number; cancelled: boolean }>;
    menu(args: { title?: string; message?: string; actions: { id: string; title: string; style?: string }[] }): Promise<{ id?: string; index?: number; cancelled: boolean }>;
    datePicker(args: { title?: string; mode?: "date" | "time" | "dateTime"; value?: string; timestampMS?: number }): Promise<{ cancelled: boolean; value?: string; timestampMS?: number }>;
  };
  events: { on(name: string, handler: (detail: unknown) => void): () => void };
}

export interface HTMLAppDataAPI {
  collection(name: string): {
    put(id: string, document: Record<string, unknown>): Promise<{ ok: boolean }>;
    get(id: string): Promise<Record<string, unknown> | null>;
    remove(id: string): Promise<{ ok: boolean }>;
    query(options?: { cursor?: string; limit?: number }): Promise<{ items: { id: string; document: unknown }[]; cursor?: string }>;
    search(text: string, limit?: number): Promise<{ items: unknown[] }>;
    count(): Promise<{ count: number }>;
  };
  kv: { get(key: string): Promise<unknown>; set(key: string, value: unknown): Promise<unknown>; remove(key: string): Promise<unknown> };
  migrate(name: string, version: number, migrations: Record<number, (context: unknown) => Promise<void>>): Promise<number>;
}

export interface HTMLAppRuntimeAPI {
  runOperation<T>(name: string, work: (context: { signal: AbortSignal }) => Promise<T>, onState?: (state: unknown) => void): Promise<T>;
  cancelOperation(name: string): boolean;
  readonly activeOperations: string[];
  readonly isVisible: boolean;
  onActive(handler: (detail: unknown) => void): () => void;
  onInactive(handler: (detail: unknown) => void): () => void;
  onBackground(handler: (detail: unknown) => void): () => void;
  onResume(handler: (detail: unknown) => void): () => void;
}

declare global {
  interface Window { HTMLAppNative?: HTMLAppNativeAPI; HTMLAppData?: HTMLAppDataAPI; HTMLAppRuntime?: HTMLAppRuntimeAPI }
}
