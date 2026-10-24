# HTMLApp 1.6.16 (build 23)

## Lock Screen microphone

The Lock Screen voice widget uses `htmlapp://voice-create` to open the ordinary Generate with AI page and begin dictation after unlocking. A tap stops the initial recording. Thereafter the same microphone uses the usual hold-to-talk gesture: press, speak, and release. Forge waits for Whisper transcription before submitting a recording. The deep-link request is kept in app state and UserDefaults so the cold-launch event is not lost if the Library view subscribes late; a competing What's New cover is dismissed before routing.

## Import HTML from a URL

An app or shortcut can open HTMLApp with a URL like:

```text
htmlapp://import?url=https%3A%2F%2Fexample.com%2Fmy-app.html
```

The query parameter `url` must be percent-encoded and point to a **public HTTPS** HTML document. HTTP, loopback/local hosts, credentials, and redirects to unsafe schemes/hosts are rejected. The download uses an ephemeral session and a 12 MB size limit. The document opens as an **unsaved** Forge edit draft, preserving the downloaded HTML. Nothing enters the Library until the user taps Save App. Running imported HTML can execute scripts in the normal HTMLApp preview sandbox, so use links from sources you trust.

## More faithful style choices

Mockups are independently requested from AI with distinct layout directions and a light/dark mode matching the device, unless the user's prompt explicitly specifies another appearance. If the AI endpoint fails or returns unusable content, the fallback now contains product-specific sample content for common app categories and three different layouts. The AI debug trace records each provider failure instead of silently hiding why local fallback was used.

## QUICK!

Set **QUICK! model name** under Settings → AI & Creation. The Generate with AI page then offers a QUICK! toggle. When on, it uses that model on the standard provider for the AI roles in the current run, streamlines preflight research, and avoids optional UI overhaul. During normal creation, Skip buttons can cancel optional prompt-improvement and icon requests; during UI overhaul, Skip preserves the functional HTML from before the cosmetic pass.

## Hands-on onboarding

The practice calculator guides the user through changing a prompt, watching simulated generation, pressing real calculator buttons, dragging the floating mic, typing and applying an edit, and a simulated save. These actions do not call a provider or modify the Library.

## Verification

- `python3 scripts/test-source-invariants.py` — passed.
- `node scripts/test-widget-bridge.js` — passed.
- Xcode compilation, WidgetKit cold-launch behavior on iOS 16.2, microphone authorization, external-link downloads, AI provider responses, and all screen layouts require device testing.
