# Current on-device background handoff (HTMLApp 1.6.18)

HTMLApp now has a file-backed `URLSessionConfiguration.background` coding request
path for backgrounded Forge work. Foreground work retains streaming and live
preview. When the app enters the background during an active generation or edit,
HTMLApp saves a checkpoint, submits a non-streaming request using the configured
AI provider and cancels the foreground stream. This may start a new provider
request, so the provider may charge for both requests. It is not a server worker.

The system can continue the upload and download the response while HTMLApp is
suspended, subject to iOS scheduling and network conditions. The app delegate
reconnects to the background session after a system relaunch. A complete response
is written into the existing Forge draft checkpoint, with a local purpose-aware
icon-script fallback if necessary. WebKit verification and icon rendering happen
only after foreground return. A local notification is attempted if notifications
were already authorized. A failed, incomplete or rejected background response
leaves the earlier checkpoint for recovery.

The earlier `beginBackgroundTask` grace period remains, as does the iOS 26
`BGContinuedProcessingTask` integration. None of these can guarantee completion,
especially after a user force-quits the app, or with a non-HTTPS provider. The
server-worker architecture below is an older future proposal and is **not**
implemented or required.

---

# Background Forge generation and editing: implementation plan

## Product contract
Users may start a generation or edit, leave HTMLApp, and come back to a durable job result.
Show a job in Forge > Activity with queued / researching / planning / coding / verifying /
completed / failed / canceled states; retain partial progress, final HTML, app icon/assets,
verification report, model selections, and failure diagnostics. Do not require location
or microphone/audio/background navigation to prolong runtime. Work initiated on one
device should be visible on another only after explicit account-based sync is enabled.

## Execution architecture
**Reliable path (all iOS versions including 16.2):** a user-opted-in background
Forge worker running on a server. The iOS app submits a job with a stable UUID,
input HTML or prompt, selected models/tasks, stage config, and generation options.
The worker runs planner -> research -> code/patch -> assets/icon -> QA and stores
immutable stage outputs and the final artifact. The phone polls while foregrounded;
APNs sends a completion notification when configured. On reopen, the app resumes
from its durable cursor rather than restarting from scratch. Optionally expose
SSE for streaming progress while the app is foregrounded.

**On-device opportunity:** iOS 26+ `BGContinuedProcessingTask` can be used for
foreground-initiated jobs to continue temporarily after the app is backgrounded,
but execution is still discretionary and isn't a substitute for server workers.
On iOS 16, `beginBackgroundTask` permits a short grace period to save state and
complete small in-flight operations, not unlimited AI generation. `BGProcessingTask`
may run later at an unpredictable time; use only as optional sync/resume, never
the sole promise of generation completion.

**Live Activities:** a progress viewer, not an execution mechanism. ActivityKit
can reflect stage/status through APNs Live Activity pushes from the server where
supported; on iOS 16.2, respect family/version compatibility. Do not claim a
Live Activity holds the app process alive.

## Worker API (to implement before exposing switch in Settings)
- POST /v1/forge/jobs -> 202 {id,status,createdAt} (idempotency key required)
- GET /v1/forge/jobs/:id -> status, stage, progress, revisions, completion metadata
- GET /v1/forge/jobs/:id/events -> stage updates (SSE; foreground only)
- POST /v1/forge/jobs/:id/cancel -> cooperative cancellation
- GET /v1/forge/jobs/:id/result -> authenticated final HTML/asset bundle and checksum
- POST /v1/forge/devices -> register scoped APNs token; optionally ActivityKit push token

Store stage checkpoint after every completed agent task, lock jobs to a single
worker lease, retry transient provider failures with backoff, bound token and cost
budgets, scrub secrets from logs, encrypt saved jobs/assets, expire old content, and
require per-account authentication. Never put an AI API key in generated HTML,
widgets, share exports, logs, public URLs, or APNs payloads. If users BYO an
AI API key, either keep processing local-only or provide a separate explicit,
encrypted, revocable consent flow to use that key on the worker.

## iOS integration
Persist local job id, source app id, edit base revision hash, job status, updatedAt,
and last-known checkpoint. Reconcile state on app launch/foreground. Allow jobs to
be inspected or canceled from Settings/Forge. When applying an edit result, compare
the current HTML revision to the job's base hash and offer conflict review rather
than silently overwriting intervening edits. Never auto-save corrupt or failed HTML.

## Rollout acceptance
1. iOS 16.2: start an app generation, lock the device, return later, result exists.
2. iPadOS 26: edit an app, switch away, result completes and is reviewable.
3. Leave app during coding/asset/QA stages; job checkpoints survive restart.
4. Offline/timeout/provider 429: bounded retry + meaningful error in UI.
5. Cancellation stops billing or clearly reports in-flight provider cancellation limit.
6. Different account cannot access job, HTML, assets, or API credentials.
7. Edit revision conflicts preserve both versions and never discard user changes.
8. ActivityKit displays status only; does not imply guaranteed execution time.
9. Existing website import, HTML file import, offline apps and widgets unaffected.

## Current state
The native HTMLApp repo does **not** yet provide this server-side worker/job API.
Do not advertise reliable background Forge generation until the worker is deployed,
authenticated and end-to-end tested. Existing BGAppRefresh JSON polling is only for
small public-data refresh jobs created by HTMLApps, not for Forge's AI pipeline.
