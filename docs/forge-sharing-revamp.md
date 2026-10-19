# Forge and sharing update

Original group selection now requires common signed declaration plus actual main-container access; an unavailable original group is disabled with installation requirements. A valid provider group remains selected after a rejected switch. This does not grant entitlements or change Apple authorization. Existing TrollStore data paths remain intact.

Forge adds a bounded Google-first reader with DuckDuckGo fallback, explicit no-key catalog action, official-documentation verification instructions, adaptive iPhone/iPad interaction constraints and a visible activity/evidence panel. Catalog listings are leads; search availability is not guaranteed. Provider settings and custom prompt text are preserved. Product constraints are appended to the coding prompt. Cancelling the view cancels its active generation task.

Dictation uses Apple Speech without a third-party API key, preferring supported on-device recognition. Otherwise it may require Apple network processing and the OS permission. The transcript is editable before generation. Recording stops on exit/background or after 55 seconds. No paid or anonymous third-party STT endpoint is assumed.

Web Clip installation now opens a tokenized loopback HTTP profile download, bound to 127.0.0.1 only, instead of attempting UIApplication.open(data:). The listener lasts at most 60 seconds or the granted background time. Safari download and Settings installation remain user-mediated. Export Profile is retained. Physical Safari download remains a release test.

Experimental Nearby Transfer uses encrypted Multipeer Connectivity with explicit connection acceptance, explicit sending and receiver confirmation before merge-only import. iOS chooses Wi-Fi/Bluetooth; Bluetooth-only routing or superior speed is not claimed. It uses the existing portable backup format and a 100 MB limit. Keychain secrets, provider credentials and permission grants are not transferred. Discovery/transfer stops in background; use Export/AirDrop for larger archives. Real-device radio, locale speech recognition and signing profile availability cannot be established by unit tests.
