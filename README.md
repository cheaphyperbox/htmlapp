# HTMLApp

HTMLApp is an iPhone-only iOS 16+ application for saving and running user-provided HTML as full-screen local apps.

## Current development features

- SwiftUI library interface
- Add, preview, update, duplicate, and delete saved HTML apps
- Automatic `<title>` extraction
- Remote or embedded favicon detection when available
- Unique six-character app IDs
- Deep links using `htmlapp://open?id=123456`
- Context-menu actions for HTML, IDs, URL schemes, source refresh, duplication, and deletion
- Search ranking by name, description, visible body text, then raw HTML
- Persistent local JSON library
- Full-screen `WKWebView` runner with interactive dismissal disabled
- Onboarding and settings screens
- Per-app media permission prompt foundation
- Static external-source discovery and three-day cache refresh foundation
- iPhone-only target with iOS 16.0 minimum deployment
- Unsigned IPA build on every push to `main`

## Building

GitHub Actions generates the Xcode project with XcodeGen, builds an unsigned device app, packages it as `HTMLApp-unsigned.ipa`, and uploads it as a workflow artifact.

An unsigned IPA must be signed by the installation method before iOS will install it.

## Development notes

The current source-cache implementation downloads discoverable static HTTP/HTTPS resources and preserves stale copies when refreshing fails. Rewriting HTML and CSS references to guaranteed local cached URLs, nested CSS dependency traversal, persistent per-ID permission choices, location bridging, import/export, and permission management remain active development work.

This repository uses only its default `main` branch for development.
