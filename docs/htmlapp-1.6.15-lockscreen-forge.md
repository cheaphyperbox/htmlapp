# HTMLApp 1.6.15 (build 22)

## Lock Screen voice handoff

The Lock Screen voice widget now opens the standard **Generate with AI** page. Its microphone begins listening on appearance; the red stop button and the instruction **Tap to stop recording** remain visible until capture stops. Tapping **Start Generating** stops capture and uses the transcribed text, or waits for a selected Whisper offline transcription to finish first. **Cancel** discards any recording in progress.

The former dedicated voice-capture modal was removed. A normal, manually opened Generate with AI page retains the existing hold-to-dictate gesture. A dismissed widget-entry presentation resets the microphone mode.

## What's New

The redundant navigation-bar **Done** action was removed. The bottom **Continue to HTMLApp** button remains.

## Verification

- `python3 scripts/test-source-invariants.py`: passes for version 1.6.15 (22).
- `node scripts/test-widget-bridge.js`: passes.
- iOS build, Apple Speech permissions, Whisper transcription, widget launch transitions, and real-device recording duration still require Xcode/device validation.
