# ncm_api

Pure-Dart client for the Netease Cloud Music private API. No Flutter dependency —
usable from any Dart program. Implements the WEAPI / EAPI / LinuxAPI request
encryption schemes and typed endpoint wrappers.

## Quick start

```dart
import 'package:ncm_api/ncm_api.dart';

final client = NcmClient();

// Search (eapi)
final res = await client.search('周杰伦 稻香', limit: 3);
final songs = res['result']?['songs'] as List? ?? const [];

// Song detail (weapi) + playable URL (eapi, quality tiers)
final detail = await client.songDetail([347230]);
final urls = await client.songUrl([347230], level: SongLevel.exhigh);

// Lyrics (plain api)
final lyric = await client.lyric(347230);
```

### QR login

```dart
final unikey = await client.loginQrKey();          // eapi @ interface
final qrUrl  = client.loginQrCodeUrl(unikey);       // encode into a QR image
// Poll every ~2s until code 803 (authorized):
final resp = await client.loginQrCheck(unikey);     // eapi @ interfacepc
// On 803 the session cookies (MUSIC_U, __csrf, …) are ingested into
// client.cookieJar automatically. Persist client.cookieJar.toMap().
```

See `example/qr_login.dart` for a terminal-QR end-to-end demo.

### Sessions & device identity

- **Session:** persist `client.cookieJar.toMap()`, restore with
  `NcmClient(cookieJar: CookieJar.fromMap(...))`.
- **Device:** persist `client.device.toMap()`, restore with
  `NcmClient(device: Device.fromMap(...))`. Keep the device **stable across
  launches** — a fingerprint that changes every run reads as suspicious to
  Netease risk control.

## Encryption schemes

All AES is AES-128, PKCS7 padding (matches Node's `createCipheriv` defaults).
Verified byte-for-byte against a Node `crypto` reference (`test/crypto_test.dart`).

| Scheme     | Algorithm                                             | Used by |
|------------|-------------------------------------------------------|---------|
| `weapi`    | AES-CBC(preset) → base64 → AES-CBC(randKey) + RSA wrap | web endpoints, `song/detail`, login/cellphone |
| `eapi`     | MD5 digest + AES-ECB(eapiKey), hex                    | `interface(pc)` endpoints, `song/url/v1`, search, **QR login** |
| `linuxapi` | AES-ECB(linuxKey), hex                                | `/api/linux/forward` |
| `api`      | plaintext form POST (no encryption)                   | `lyric`, `playlist/detail` |

RSA is raw modular exponentiation (`m^e mod n`, e=65537), input left-padded to
128 bytes — equivalent to Node's `RSA_NO_PADDING`. Implemented with `BigInt`
(no pointycastle needed for RSA).

## Protocol notes / gotchas

Hard-won during bring-up (2026-08). These are non-obvious and load-bearing.

### QR login MUST use the eapi @ interface channel

The unikey (`loginQrKey`) **and** the status poll (`loginQrCheck`) must both
travel `eapi` on the `interface(pc).music.163.com` hosts with `type: 3`.

- A unikey minted on the classic `weapi @ music.163.com` path binds to a
  different device/session context. The server then returns **code 803
  ("authorized")** on check but **withholds the login cookies** — you get a
  successful-looking response with only `NMTID`, never `MUSIC_U`.
- `music.163.com` sits behind a CDN (`volc-dcdn`) that **strips `Set-Cookie`**
  from login responses entirely. Even a correct request there yields 0 cookies.

The fix: key + check both on `eapi @ interface`. On 803 the real response
carries ~28 `Set-Cookie` lines (`MUSIC_U`, `MUSIC_A_T`, `MUSIC_R_T`,
`MUSIC_R_U`, `__csrf`, …). Regression-guarded in `test/qr_login_test.dart`.

### Login-state detection

`loginStatus()` (`/weapi/w/nuser/account/get`) returns `profile` at the **top
level** — `{code, account, profile}` — NOT nested under `data`. A logged-in
session has `profile.userId`; a guest has `profile == null`. Presence of
`MUSIC_U` in the jar is the primary "logged in" signal; `profile` validates it.

### EAPI responses: ciphertext OR plaintext

`eapi` endpoints may return AES-ECB **ciphertext** or **plaintext JSON**
depending on the endpoint/time. The request pipeline tries `eapiDecrypt` first,
then falls back to raw JSON parse. (`cloudsearch/pc` currently returns plaintext.)

### Set-Cookie capture

Netease sends many repeated `Set-Cookie` headers whose `Expires` attribute
contains a comma. `package:http`'s `Response.headersSplitValues` recovers the
individual lines; `CookieJar.ingestSetCookies` keeps only the leading
`name=value` of each, discarding `Max-Age/Expires/Path`. Verified against both a
local dart:io server and the live server.

### Anonymous (guest) token

The bundled `kAnonymousToken` is a static fallback. The classic
`weapi/api register/anonimous` endpoints now **reject** guest registration
(code 400); a fresh token requires the newer `xeapi` flow (X25519 + AES-GCM),
which is **not implemented here**. Guest reads that still accept the static
token work; anything requiring a fresh guest session needs login.

## Testing

```sh
dart test          # crypto vectors, device encoding, cookie capture, login channel
dart run example/qr_login.dart   # live QR login (needs a phone scan)
```

`example/smoke.dart` exercises the public read endpoints against live servers.
