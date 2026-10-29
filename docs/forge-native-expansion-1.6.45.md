# HTMLApp 1.6.45 (53) — Forge and native bridge development status

This document is a truthful source-level inventory. It does **not** claim that an
Xcode build, IPA signing, or physical iPhone verification succeeded.

## Implemented in this release's source

**Forge planning and editing**
- Stable native capability instructions are before dynamic research for improved
  provider prompt-prefix caching.
- Planner-only sampling uses a creative temperature on supported first-party
  non-reasoning models, or medium reasoning effort for suitable OpenAI reasoning
  models; coding calls remain conservative.
- Optional on-device visual taste notes summarize selected CSS tokens and a small
  set of recurring visual edit preferences; off by default, clearable in settings,
  and appended after the dynamic AI prompt cache boundary.
- Small edits to large HTML files with explicit, unambiguous CSS selectors may
  pass a bounded source excerpt rather than the entire file. Full-source fallback
  is used when selection is ambiguous; patches are applied to the original.
- Dictated new-app prompts enter the planner and carry a speech-context correction
  instruction even if ordinary quick-mode text would have skipped preflight.
- Apple Speech adds punctuation and app-building vocabulary hints.
- Bridge lint checks unknown methods and some empty calls requiring arguments.

**Native capabilities**
- HealthKit `health.range(quantity,start,end)`: bounded cumulative date-window
  reads, including `hasData` for missing data.
- NFC `nfc.writeText(text)`: single-tag foreground NDEF text writes with a
  destructive-operation confirmation, capacity/writable checks, and size limit.
- Bluetooth GATT: read/write a previously scanned device characteristic,
  bounded writes/timeouts, one foreground notify subscription and teardown.
- Core Image `image.filter(url,effect)`: file-backed local JPEG effects (mono,
  sepia, invert, blur), no large JS data URL responses.
- PDFKit `pdf.inspect(url)`: local page counts and bounded extracted text.
- VisionKit `documents.scan()`: camera-permission-gated, foreground native
  document scanner with app-owned scanned page files.
- PencilKit `drawing.open()`: foreground drawing sheet returning a private PNG.
- Core Haptics `haptics.pattern(pulses)`: small bounded transient patterns,
  cleaned up on app exit.
- GameController `gamepad.list/start/stop`: foreground controller events,
  capped to roughly 30 Hz, with teardown on app exit.
- Apple Foundation Models `ai.localAvailable/localComplete`: eligible iOS 26+
  local text and JSON inference, permission gated, four calls/minute, no network AI.

All methods are documented in the existing device capability catalog, with
native bridge wrappers and source-level regression assertions.

## Not yet implemented from the requested list

- Dynamic provider role selector/temperature controls for every provider;
  extended thinking for Anthropic/planner/verifier model families.
- A complete opt-in taste inference pipeline including kept/deleted apps,
  one-tap planner assumption and voice interpretation confirmation.
- Version-tested WhisperKit vocabulary prompt tokens, selectable larger local
  model, and confident multilingual decoding.
- A single generated machine-readable registry that entirely replaces the
  existing switch, wrappers, catalog and documentation.
- Full action-observing WebKit bridge QA mocks, multi-device acceptance and
  systematic accessibility/screenshot evaluation suites.
- Streamed model-generated tool calls or validated arbitrary schemas in
  generated apps; persistent on-device agent execution.
- Live camera frames, Vision pose/hand/depth/segmentation and general CoreML
  model compilation/inference.
- ARKit/RealityKit live tracking/anchors and LiDAR scenes.
- CoreMIDI and AVAudioEngine microphone FFT/pitch/synthesis.
- Bonjour, per-app sandboxed TCP/UDP/websocket/local HTTP server protocols.
- NearbyInteraction UWB, AirPods head tracking and general high-rate motion.
- HomeKit/Matter control, geofencing, background audio/processing, silent push.
- Interactive WidgetKit/AppIntents/Control Center, typed Siri/Shortcuts entities.
- Multi-user CloudKit sharing, persistent folder bookmarks, ReplayKit video,
  SharePlay and a Metal/WebGPU compatibility compute service.
- More native UI beyond existing native tabs/PencilKit and tested PDF rendering.
- Full device entitlement/provisioning verification, test fixtures, and
  standalone QA for each newly introduced native method.

Some of these require signing capabilities, hardware, iCloud setup or a
per-user backend. Do not advertise a feature to generated apps until it has a
real documented handler and runtime permission checks.

## Verification and build instructions

- Source file locations, method wrappers and the matching capability catalog
  were inspected.
- A V8 syntax check parsed the JavaScript source embedded in
  `HTMLAppV3/NativeAPIBridge.swift`.
- Source-regression assertions were added to
  `scripts/test-source-invariants.py` but the full script was **not executed**
  on a checked-out repository in this environment.
- No Xcode/iOS SDK compile, simulator test, device permission test, IPA package
  or network integration test was executed.
- This is **a test-build candidate, not a release-ready validation**.

To test, sync the separate build fork from `mekabrine/htmlapp` `main`;
build in its existing GitHub Actions runner and capture full failed steps
before changing upstream again. Do not directly edit the fork.
