# Saved-app AI bridge (initial implementation)

The global **Allow saved apps to request AI** switch is off by default. Each saved app must additionally receive its own AI permission. Prompts and system text are sent to the configured provider; the page never receives its API key or provider URL. The bridge currently supports `ai.available()`, `ai.complete({prompt,system?,maxTokens?})`, and `ai.classify({text,labels})`. Classification confidence is `null` because generative output is not calibrated. Per-app limit: 10 requests per rolling minute, prompt up to 8192 UTF-8 bytes, system up to 2048 bytes. `ai.available()` reports remaining requests. Handle errors `ai_disabled`, `ai_unavailable`, `permission_denied`, `rate_limited`, `prompt_too_large`, and `ai_request_failed`.

Not yet implemented: cancellable token streaming, on-device Foundation Models, per-app cumulative usage UI, Vision, structured database, Spotlight, HealthKit, NFC, MapKit bridge, stable origin migration, compact-generation scaffold, automated flow testing and architectural splits. The Compact output toggle currently saves a preference but intentionally uses the existing generation path until the scaffold is implemented.

## Manual verification

On a signed iPhone build, enable the global switch, open a saved app and request AI. Confirm per-app permission prompt and denial behavior; repeat ten times to verify throttling; verify provider errors do not reveal credentials. Disable global switch and confirm subsequent requests fail. Confirm preview mode denies access. The implementation has not been Xcode-compiled or hardware-tested.
