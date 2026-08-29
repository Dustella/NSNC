# NSNC — Non-Sucking Netease Cloudmusic

A native, cross-platform Netease Cloud Music client built with Flutter. Runs on
Windows, macOS, Linux, Android and iOS from one codebase.

## Architecture

```
NSNC/
├── packages/ncm_api/        # Pure-Dart Netease API client (no Flutter dep)
│   ├── lib/ncm_api.dart      #   barrel: NcmClient, NcmCrypto, CookieJar, Device
│   ├── lib/src/              #   crypto · cookie_jar · request · device · ncm_client
│   ├── test/                 #   crypto vectors, device, cookie capture, login channel
│   └── example/              #   qr_login.dart (live QR login), smoke.dart
├── lib/
│   ├── models/track.dart     # Normalized song model (absorbs ar/al/dt shapes)
│   ├── services/             # app_state · player_service · session_store
│   ├── ui/                   # home_shell · discover · search · library · login · player
│   └── main.dart             # MediaKit init + provider tree + theme
├── test/                     # widget render tests
└── integration_test/         # on-device playback test (real audio)
```

**Layering:** the API package is Flutter-free and independently testable. The
app depends on it via a path dependency and adds playback (media_kit), state
(provider), persistence (shared_preferences), and the UI.

## Key components

- **API** (`packages/ncm_api`) — WEAPI/EAPI/LinuxAPI encryption + typed
  endpoints (login, search, song detail/url, lyrics, playlists, discovery).
  See its [README](packages/ncm_api/README.md) for protocol notes.
- **Player** (`lib/services/player_service.dart`) — media_kit (native mpv on
  every platform). Owns the queue, resolves per-track stream URLs lazily,
  handles shuffle / repeat / seek.
- **Session** (`lib/services/session_store.dart`) — persists the cookie jar
  (auth) and the device identity (stable fingerprint) across launches.

## Running

```sh
flutter pub get
flutter run -d windows      # or macos / linux / <device-id>
```

Login is QR-based: open the login screen, scan with the Netease Cloud Music app,
confirm on your phone. The session persists across restarts.

## Verifying

```sh
# API package (pure Dart)
cd packages/ncm_api && dart test

# App analysis + widget render tests
flutter analyze
flutter test

# On-device playback (real audio, needs a desktop/device target)
flutter test integration_test/playback_test.dart -d windows

# Live QR login end-to-end (terminal QR, needs a phone scan)
cd packages/ncm_api && dart run example/qr_login.dart
```

## Notes

- **Login channel:** QR login must use the `eapi @ interface` hosts, not the
  classic `weapi @ music.163.com` path (which is behind a CDN that strips login
  cookies). Details in the API package README.
- **Device fingerprint:** kept stable across launches to stay off Netease risk
  control. Persisted alongside the session.
- **Audio backend:** media_kit / libmpv. Streams mp3/flac, gapless, precise seek.

## License

[WTFPL, Version 2](LICENSE)
