#!/bin/sh
# check-libs.sh <app-dir> [extra-library-path]
#
# Runs inside a clean container after a package is installed. Fails if the
# Flutter bundle has an unresolved shared library (including glibc symbol
# versions), or if libmpv.so.2 cannot be dlopen'ed the way media_kit does it.
set -eu

app="$1"
if [ -n "${2:-}" ]; then
  LD_LIBRARY_PATH="$2${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  export LD_LIBRARY_PATH
fi

fail=0
for f in "$app/nsnc" "$app"/lib/*.so; do
  # Plugins find libflutter_linux_gtk.so through the executable's
  # RUNPATH ($ORIGIN/lib) at runtime, so give ldd the same directory.
  # libdartjni.so (from package:jni) only needs libjvm when a JVM is used,
  # which never happens on desktop Linux.
  missing="$(LD_LIBRARY_PATH="$app/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ldd "$f" 2>&1 \
    | grep 'not found' | grep -v 'libjvm\.so' || true)"
  if [ -n "$missing" ]; then
    echo "Unresolved libraries for $f:"
    echo "$missing"
    fail=1
  fi
done

# media_kit loads libmpv at runtime by soname, so ldd alone cannot see it.
perl -MDynaLoader -e '
  DynaLoader::dl_load_file("libmpv.so.2", 0)
    or die "dlopen libmpv.so.2 failed: " . DynaLoader::dl_error() . "\n";
  print "libmpv.so.2 loads\n";
' || fail=1

[ "$fail" -eq 0 ] && echo "OK: all libraries resolve"
exit "$fail"
