# Generation Music

Settings → AI & Creation → Generation Music lets users supply a direct audio-file URL, enable music that plays during generation, adjust volume, and preview it.

The downloaded file is cached for later runs. Playback starts when Forge starts building or editing an app and stops when the run ends. A failed download does not prevent app creation. The iOS audio background mode permits playback when the screen locks, subject to operating-system audio policies.

Use audio URLs you have permission to access. Links should resolve directly to supported MP3, M4A, WAV, AAC or CAF audio. Files exceeding 80 MB are rejected. HTTPS is recommended.

## Background playback

Generation Music uses the iOS playback audio session and Now Playing controls, so a cached track can keep playing when the device is locked or when HTMLApp is in the background. Playback is stopped when HTMLApp learns that the Forge run has finished or been canceled. Lock-screen playback is subject to iOS system behavior; force-quitting the app stops its process and is not supported as a way to finish a Forge run. Background audio does not grant unlimited background execution to network requests or the Forge pipeline. HTMLApp's separate background-upload/checkpoint path handles generation continuation where available.
