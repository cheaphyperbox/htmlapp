# Native bridge contract and code generation

The authoritative native RPC method registry is `scripts/native-capability-definitions.json`. It declares every method's name, host permission, minimum iOS version, user-initiation expectation, native cancellation support, recognized input types and required arguments. The registry is deliberately separate from iOS entitlement and device availability.

Run `node scripts/generate-native-contract.js` after editing the schema. This updates:

- `HTMLAppV3/HTMLAppBridgeRegistry.swift` — Swift method inventory, argument-shape validation, permissions, and self-describing method metadata.
- `docs/htmlapp-native-api.json` — machine-readable method definitions.
- `docs/htmlapp-native-api.d.ts` — typed method union and public runtime interfaces, using the manually maintained higher-level SDK signatures in `scripts/native-contract-types.json`.

CI invokes the generator with `--check`, compares all three outputs, cross-checks the method list against the native Swift switch, compiles the generated registry on Linux, validates required parameters and types, and checks the JavaScript SDK's calls. A method is not considered supported merely because it was added to the schema: the native dispatcher and JavaScript SDK must implement it and CI rejects orphaned entries.

## Adding a new native capability

1. Implement a permissioned and bounded Swift service; do not trust arbitrary paths, hosts, binary sizes or JS arguments.
2. Add a `case` to `HTMLNativeAPIBridge.handle`, preserving the central main-frame/origin gate and using `HTMLPermission` when appropriate.
3. Register its method and input metadata in `scripts/native-capability-definitions.json`, then regenerate.
4. Add a typed `HTMLAppNative` wrapper and `HTMLAppDeviceAPIResearch` entry when this should be offered to Forge. Add the TypeScript shape to the trailer.
5. Add unit tests for success/denied/cancel/unsupported and a device fixture where hardware is involved.

`HTMLAppBridgeRegistry.argumentIssue` validates only known top-level argument types and presence. It **does not** replace service-specific validation of ranges, URLs, media identifiers, permission timing, file scopes or payload size.

## Protocol boundaries

`HTMLAppNative.call(method,args,{signal})` sends a request identifier through WKScriptMessageHandler and resolves or rejects a Promise. AbortSignal rejects the JavaScript Promise; only methods marked with `nativeCancellation: true` promise to stop a running native operation. Event-based hardware updates use documented `htmlapp:*` custom events. There is not yet a universal binary stream transport or guaranteed arbitrary background execution.

The host's per-saved-app policy and iOS system authorization are **independent**. `capabilities.describe(method)` reports implementation and hardware facts but cannot grant a permission or Apple entitlement. Preview mode intentionally restricts hardware operations.

## User-interface quality

Every generated/saved app is subject to document-level horizontal overflow and page-zoom prevention in its WKWebView host. Intentional horizontal-scrolling components are opt-in, marked with `data-htmlapp-horizontal-scroll="true"`. Offscreen QA inspects phone/iPad widths; it does not replace actual-device tests.
