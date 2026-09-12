# PortableAI iOS

SwiftUI client for the PortableAI server (separate repo). Pair over LAN,
chat with personas, pin conversation exports offline.

**API ground truth:** `../portableai/docs/API_CONTRACT.md` on this Mac
(sibling checkout). Do not invent field names.

## Brand assets

One-time copy from the server repo’s web UI — see
`PortableAI/Resources/BRAND_ASSETS.md`.

- Accent `#10a37f`, sidebar `#171717`
- Logo last refreshed: **2026-09-12** (from `ui/static/logo.svg` / `logo.png`)

## Build

```bash
open PortableAI.xcodeproj
# or:
xcodebuild -scheme PortableAI -destination 'generic/platform=iOS Simulator' build
```

## Features

- **Chats** in the sidebar: `GET /api/conversations` + open full history via `GET /api/conversations/<id>`; swipe to delete
- **Pinned**: local export snapshots via `PinnedChatsStore` (readable offline / airplane mode)
- **Model picker** in chat toolbar: optional `model_override` on `POST /api/chat` (default = persona `FROM`)

## LAN test

1. Ubuntu host: Settings → Phone pairing → copy `http://<lan-ip>:5050` + PIN
2. Manual PIN entry on device (QR camera path is optional / flaky on some phones)
3. Confirm persona list shows `display_name` + `base_model`, default persona
   opens, chat round-trips
