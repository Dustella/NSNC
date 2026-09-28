# Building and releasing

All release packages are built by GitHub Actions in
[`.github/workflows/build.yml`](../.github/workflows/build.yml). Nothing needs
to be built by hand for a release.

## What CI builds

| Job | Runner | Output | Signing |
|---|---|---|---|
| Windows | `windows-latest` | `nsnc-<ver>-windows-x64.zip`, `.msi` | unsigned |
| Linux | `ubuntu-24.04` | `.tar.gz`, `nsnc_<ver>_amd64.deb`, `nsnc-<pkgver>-<rel>-x86_64.pkg.tar.zst`, `nsnc-<ver>-x86_64.AppImage` | unsigned |
| macOS | `macos-latest` | `nsnc-<ver>-macos-universal.dmg`, `.zip` (x86_64 + arm64) | ad-hoc only, not notarized |
| Android | `ubuntu-24.04` | `nsnc-<ver>-android-<abi>.apk` (arm64-v8a, armeabi-v7a, x86_64), `nsnc-<ver>-android.aab` | release upload key |
| GitHub Release | `ubuntu-24.04` | the files above plus `SHA256SUMS.txt` | — |

`<ver>` is the full `pubspec.yaml` version, e.g. `0.1.0+1`.

Triggers: pull requests, pushes to `main`, `v*` tags, and manual runs
(**Actions → Build packages → Run workflow**, only once the workflow is on
`main`). Each run uploads one artifact per platform, downloadable from the run
page for 90 days.

iOS is not built yet.

## Publishing a release

1. Set the version in `pubspec.yaml`, e.g. `version: 0.2.0+2`.
   - Keep it plain `x.y.z+build`. A pre-release suffix such as `-beta.1`
     breaks the MSI version.
   - Increase the build number (`+N`) on every release: it becomes the Android
     `versionCode`, and Android refuses to install a lower one over a higher one.
2. Merge the change to `main`.
3. Tag the merged commit and push the tag:

   ```sh
   git checkout main
   git pull
   git tag v0.2.0
   git push origin v0.2.0
   ```

4. Wait for the run on the tag to finish. The release job then:
   - fails without publishing if the tag is not `v` + the `x.y.z` part of
     `pubspec.yaml` (`0.2.0+2` needs `v0.2.0`);
   - creates release `NSNC v0.2.0` with notes generated from the commits since
     the previous tag, and attaches every package plus `SHA256SUMS.txt`.

Re-running the workflow for the same tag re-uploads the files to the existing
release and leaves its notes alone. To change the notes, edit the release on
GitHub.

On every non-tag run the release job is a dry run: it collects the files and
prints the checksums, but publishes nothing. If it fails on a PR, the real
release would have failed too.

## Android signing

Release APKs and the AAB are signed with an RSA-4096 **upload key**:

- alias `nsnc-upload`
- certificate SHA-256
  `91:F9:6B:EC:AD:4F:7F:2B:C2:4F:6F:21:DA:40:C7:E4:A0:CD:81:68:7C:C1:CA:23:36:9A:C5:01:26:98:1C:27`

`android/app/build.gradle.kts` signs release builds from `android/key.properties`.
Only CI writes that file, from four repository secrets, and deletes it together
with the keystore at the end of the job. Local release builds have no
`key.properties`, so they fall back to the debug key. The CI job fails if any
APK is signed with the debug key.

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | the `.jks` file, base64-encoded |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `ANDROID_KEY_PASSWORD` | key password (same as the keystore password for this key) |
| `ANDROID_KEY_ALIAS` | `nsnc-upload` |

If a secret is missing, the job stops at "Install release keystore" and names
the missing one.

### Backup

The key is backed up in Bitwarden as a Secure Note: the `.jks` attached (or its
base64 text in the note body), the passwords in hidden fields, and the alias and
fingerprint in text fields. Keep the plain copies out of the repo.

Losing the key means installed copies can never be updated: users would have to
uninstall first. If the app is ever published on Google Play with Play App
Signing, this key becomes only the upload key, and a lost upload key can be
reset through Play support.

To check a backup, restore the `.jks` and compare the fingerprint:

```sh
keytool -list -v -keystore nsnc-upload.jks -alias nsnc-upload
```

### Restoring or replacing the secrets

From a restored keystore (PowerShell):

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("nsnc-upload.jks")) |
  gh secret set ANDROID_KEYSTORE_BASE64 --repo Dustella/NSNC
gh secret set ANDROID_KEYSTORE_PASSWORD --repo Dustella/NSNC   # prompts
gh secret set ANDROID_KEY_PASSWORD --repo Dustella/NSNC        # prompts
gh secret set ANDROID_KEY_ALIAS --repo Dustella/NSNC --body nsnc-upload
```

A **new** key only makes sense before the first public release, because
existing installs will reject updates signed with a different key. It was
created with:

```sh
keytool -genkeypair -v -storetype PKCS12 -keystore nsnc-upload.jks \
  -alias nsnc-upload -keyalg RSA -keysize 4096 -validity 10000
```

## Packaging details

### Windows MSI

Source: [`packaging/windows/nsnc.wxs`](../packaging/windows/nsnc.wxs)
(WiX Toolset 5.0.2, installed in CI with `dotnet tool install`).

- Per-machine install with a UAC prompt. The default folder is
  `C:\Program Files\NSNC` and the wizard lets the user change it. It adds a
  Start Menu shortcut and an Apps & Features entry with the app icon.
- The MSI version is the pubspec version with `+` replaced by `.`
  (`0.1.0+1` → `0.1.0.1`). Newer MSIs replace older ones in place.
- **Never change the `UpgradeCode`** in `nsnc.wxs`: it is what links versions
  together for upgrades.
- CI installs the MSI silently, checks the files and the shortcut, then
  uninstalls it and checks the files are gone.

To build it locally (needs the .NET SDK):

```powershell
dotnet tool install --global wix --version 5.0.2
wix extension add --global WixToolset.UI.wixext/5.0.2
flutter build windows --release
wix build packaging/windows/nsnc.wxs -arch x64 -ext WixToolset.UI.wixext `
  -d Version=0.1.0.1 `
  -d "ReleaseDir=$((Resolve-Path build\windows\x64\runner\Release).Path)" `
  -d IconPath=windows\runner\resources\app_icon.ico -o nsnc.msi
```

`ReleaseDir` must be an absolute path, or the file harvesting finds nothing.

### Linux packages

Source: [`packaging/linux/`](../packaging/linux/). `package.sh` builds all
three packages from the Flutter release bundle, then `check-libs.sh` checks each
one in a clean container:

- `.deb` in Ubuntu 24.04, Arch package in Arch Linux, AppImage in a bare
  Ubuntu 24.04 with only desktop base libraries and no mpv;
- every shared library the app and its plugins need must resolve, and
  `libmpv.so.2` must load the same way media_kit loads it.

The GUI is never started in CI.

| Package | Installs to | Depends on | Install with |
|---|---|---|---|
| `.deb` | `/opt/nsnc`, `/usr/bin/nsnc` | `libgtk-3-0t64 \| libgtk-3-0`, `libmpv2` | `sudo apt install ./nsnc_<ver>_amd64.deb` |
| Arch | `/opt/nsnc`, `/usr/bin/nsnc` | `gtk3`, `mpv` | `sudo pacman -U nsnc-<pkgver>-<rel>-x86_64.pkg.tar.zst` |
| AppImage | self-contained | host GTK 3, GL/EGL, ALSA/PipeWire | `chmod +x`, then run it |
| `.tar.gz` | anywhere | GTK 3 and libmpv from the distro | extract, run `./nsnc` |

- Everything is built on Ubuntu 24.04, so all packages need **glibc 2.39+**
  (Ubuntu 24.04+, Debian 13+, Fedora 40+, current Arch).
- The `.deb` and Arch packages install a menu entry (`com.dustella.nsnc.desktop`)
  and a 256 px icon. The desktop file name matches the GTK application ID, so
  the window gets the right icon.
- The Arch package is a binary repackage built with `makepkg` from
  `packaging/linux/arch/PKGBUILD`. Its `pkgver` is the `x.y.z` part and its
  `pkgrel` is the build number. It is not on the AUR.
- The AppImage bundles libmpv and its codec libraries (hence ~100 MB).
  - Only `libmpv.so.2` is put on the library path; its own dependencies load
    through its RUNPATH, so bundled libraries never replace ones GTK has already
    loaded.
  - Host-level libraries (GL/EGL/DRM, X11, ALSA, PipeWire, libusb, libstdc++)
    are deliberately not bundled. libjack is bundled even though linuxdeploy
    normally excludes it, because libmpv links it directly and most desktops
    don't ship it.
  - The build tools linuxdeploy and appimagetool are pinned to specific
    releases and verified by SHA-256 in `package.sh`. appimagetool downloads
    its runtime from the AppImage "continuous" release, which is not pinned.

### macOS

- `flutter build macos` produces a universal app. The `.dmg` contains the app and
  an Applications shortcut; the `.zip` holds the same app.
- The app is only ad-hoc signed and not notarized, so Gatekeeper blocks the
  first launch. Allow it in **System Settings → Privacy & Security → Open
  Anyway**, or run:

  ```sh
  xattr -dr com.apple.quarantine /Applications/nsnc.app
  ```

- The app needs macOS 12 or newer.

## Maintenance notes

- The Flutter version is pinned in the workflow (`FLUTTER_VERSION`). Bump it
  there when upgrading Flutter.
- The actions are on their Node 24 majors (checkout v7, upload-artifact v7,
  download-artifact v8, setup-java v6). Ubuntu jobs are pinned to
  `ubuntu-24.04` rather than `ubuntu-latest`, because the Linux packages and
  their glibc requirement are tied to it. Moving to a newer Ubuntu raises the
  glibc requirement for every Linux package.
- Commits that only touch docs can skip CI by putting `[skip ci]` in the commit
  message.
- Not built yet: iOS, Linux arm64. Not signed: Windows, macOS (and macOS is not
  notarized).
