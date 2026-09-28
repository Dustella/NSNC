#!/usr/bin/env bash
# Builds Linux packages from a Flutter release bundle:
#   nsnc_<ver>_amd64.deb          Debian 13+ / Ubuntu 24.04+
#   nsnc-<ver>-<rel>-x86_64.pkg.tar.zst   Arch Linux
#   nsnc-<ver>-x86_64.AppImage    any distro with glibc 2.39+ and GTK 3
# then installs each one in a clean container and checks that every shared
# library resolves (check-libs.sh).
#
# Usage: package.sh <pubspec-version> <bundle-dir> <out-dir>
# Needs: dpkg-deb, docker, convert (ImageMagick), patchelf, curl, and
# /usr/lib/x86_64-linux-gnu/libmpv.so.2 (libmpv-dev) for the AppImage.
set -euo pipefail

version="$1"                       # e.g. 0.1.0+1
bundle="$(realpath "$2")"
out="$(realpath -m "$3")"
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
work="$(mktemp -d)"

app_id=com.dustella.nsnc
upstream="${version%%+*}"
build="${version#*+}"
[ "$build" = "$version" ] && build=1

# Pinned tool releases (sha256 from the GitHub release asset digests).
LINUXDEPLOY_URL=https://github.com/linuxdeploy/linuxdeploy/releases/download/1-alpha-20251107-1/linuxdeploy-x86_64.AppImage
LINUXDEPLOY_SHA=c20cd71e3a4e3b80c3483cef793cda3f4e990aca14014d23c544ca3ce1270b4d
APPIMAGETOOL_URL=https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage
APPIMAGETOOL_SHA=ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0
export APPIMAGE_EXTRACT_AND_RUN=1  # runners have no FUSE

mkdir -p "$out"
convert "$repo/assets/branding/nsnc_logo_1024.png" -resize 256x256 "$work/icon-256.png"

# /opt/nsnc holds the Flutter bundle; /usr/bin/nsnc points at it.
stage_root() {
  local root="$1"
  mkdir -p "$root/opt/nsnc" "$root/usr/bin" "$root/usr/share/applications" \
           "$root/usr/share/icons/hicolor/256x256/apps"
  cp -a "$bundle/." "$root/opt/nsnc/"
  ln -s /opt/nsnc/nsnc "$root/usr/bin/nsnc"
  install -m644 "$here/$app_id.desktop" "$root/usr/share/applications/"
  install -m644 "$work/icon-256.png" "$root/usr/share/icons/hicolor/256x256/apps/$app_id.png"
}

fetch() {  # url sha256 dest
  curl -fsSL -o "$3" "$1"
  echo "$2  $3" | sha256sum -c -
  chmod +x "$3"
}

in_container() {  # image script
  docker run --rm -v "$out:/out:ro" -v "$here:/packaging:ro" "$1" bash -euc "$2"
}

build_deb() {
  echo "::group::Debian package"
  local root="$work/deb"
  stage_root "$root"
  install -Dm644 "$repo/LICENSE" "$root/usr/share/doc/nsnc/copyright"
  mkdir -p "$root/DEBIAN"
  cat > "$root/DEBIAN/control" <<EOF
Package: nsnc
Version: $version
Architecture: amd64
Maintainer: Dustella <fdnoaivj@outlook.com>
Installed-Size: $(du -sk "$root" | cut -f1)
Depends: libgtk-3-0t64 | libgtk-3-0, libmpv2
Section: sound
Priority: optional
Homepage: https://github.com/Dustella/NSNC
Description: NetEase Cloud Music client
 A Flutter music client for NetEase Cloud Music.
EOF
  dpkg-deb --root-owner-group -Zxz --build "$root" "$out/nsnc_${version}_amd64.deb"
  echo "::endgroup::"
}

build_arch() {
  echo "::group::Arch Linux package"
  local dir="$work/arch"
  mkdir -p "$dir"
  stage_root "$dir/root"
  cp "$repo/LICENSE" "$dir/"
  sed -e "s/@PKGVER@/$upstream/" -e "s/@PKGREL@/$build/" "$here/arch/PKGBUILD" > "$dir/PKGBUILD"
  # makepkg refuses to run as root; dependencies are only checked at install.
  docker run --rm -v "$dir:/pkg" archlinux:base-devel bash -euc '
    useradd -m builder
    chown -R builder /pkg
    cd /pkg && su builder -c "makepkg --nodeps --noconfirm"'
  cp "$dir"/nsnc-*.pkg.tar.zst "$out/"
  echo "::endgroup::"
}

build_appimage() {
  echo "::group::AppImage"
  local appdir="$work/AppDir"
  mkdir -p "$appdir/nsnc" "$appdir/usr/lib/mpv"
  cp -a "$bundle/." "$appdir/nsnc/"
  install -m644 "$here/$app_id.desktop" "$appdir/"
  install -m644 "$work/icon-256.png" "$appdir/$app_id.png"

  # Bundle libmpv plus the dependencies the host is not expected to have.
  fetch "$LINUXDEPLOY_URL" "$LINUXDEPLOY_SHA" "$work/linuxdeploy"
  "$work/linuxdeploy" --appdir "$appdir" --library /usr/lib/x86_64-linux-gnu/libmpv.so.2
  # The host's C++ runtime is already loaded by Flutter; never shadow it.
  rm -f "$appdir"/usr/lib/libstdc++.so* "$appdir"/usr/lib/libgcc_s.so*
  # Only libmpv goes on the search path. Its own deps resolve through
  # RUNPATH, so bundled libs never override ones GTK already loaded.
  mv "$appdir/usr/lib/libmpv.so.2" "$appdir/usr/lib/mpv/"
  patchelf --set-rpath '$ORIGIN/..' "$appdir/usr/lib/mpv/libmpv.so.2"

  cat > "$appdir/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/usr/lib/mpv${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$HERE/nsnc/nsnc" "$@"
EOF
  chmod +x "$appdir/AppRun"

  fetch "$APPIMAGETOOL_URL" "$APPIMAGETOOL_SHA" "$work/appimagetool"
  ARCH=x86_64 "$work/appimagetool" "$appdir" "$out/nsnc-${version}-x86_64.AppImage"
  echo "::endgroup::"
}

verify() {
  echo "::group::Verify .deb on Ubuntu 24.04"
  in_container ubuntu:24.04 '
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq /out/nsnc_*_amd64.deb >/dev/null
    test -x /usr/bin/nsnc
    sh /packaging/check-libs.sh /opt/nsnc'
  echo "::endgroup::"

  echo "::group::Verify Arch package"
  in_container archlinux:latest '
    pacman -Syu --noconfirm --needed perl >/dev/null
    pacman -U --noconfirm /out/nsnc-*.pkg.tar.zst >/dev/null
    test -x /usr/bin/nsnc
    sh /packaging/check-libs.sh /opt/nsnc'
  echo "::endgroup::"

  echo "::group::Verify AppImage on Ubuntu 24.04 (GTK + ALSA only, no mpv)"
  # linuxdeploy never bundles host-level libraries such as libasound, so the
  # container gets what a minimal desktop already has, and nothing mpv-specific.
  in_container ubuntu:24.04 '
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends libgtk-3-0t64 libasound2t64 >/dev/null
    if dpkg -s libmpv2 >/dev/null 2>&1; then echo "libmpv2 unexpectedly installed"; exit 1; fi
    cd /tmp && cp /out/nsnc-*.AppImage app && ./app --appimage-extract >/dev/null
    sh /packaging/check-libs.sh /tmp/squashfs-root/nsnc /tmp/squashfs-root/usr/lib/mpv'
  echo "::endgroup::"
}

build_deb
build_arch
build_appimage
verify
ls -l "$out"
