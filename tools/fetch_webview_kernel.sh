#!/usr/bin/env bash
#
# Fetch the WebView kernel that the `legacy` build bundles.
#
# A Chromium build is ~85 MB, so it is deliberately not committed to the repo.
# Run this once before building the legacy flavour; the build fails loudly if
# the asset is missing, rather than silently producing a legacy APK that cannot
# do the one thing it exists to do.
#
# The APKs come from https://github.com/JonaNorman/WebViewPackage, which
# archives vendor WebView builds for exactly this purpose.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/app/android/app/src/legacy/assets/webview"

# AOSP rather than Google's build: it is the most straightforward to
# redistribute, and the legacy flavour exists for old devices where the
# difference does not matter.
VENDOR="${DSH_WEBVIEW_KERNEL_VENDOR:-android}"
ABI="${DSH_WEBVIEW_KERNEL_ABI:-armeabi-v7a}"
# min24 keeps the legacy build's own minSdk honest. Chromium 113 is far above
# the Chromium 94 the DSH bundle needs, and the newer arm32 builds all require
# API 26, which would lock out the very devices this flavour targets.
VERSION="${DSH_WEBVIEW_KERNEL_VERSION:-113.0.5672.136_min24_arm32}"
MIRROR="${DSH_WEBVIEW_KERNEL_MIRROR:-https://ghproxy.net/}"

URL="https://github.com/JonaNorman/WebViewPackage/releases/download/$VENDOR/$VERSION.apk"
OUT="$DEST/$ABI.apk"

mkdir -p "$DEST"

if [ -f "$OUT" ]; then
  echo "already present: $OUT ($(du -h "$OUT" | cut -f1))"
  echo "delete it first to re-download."
  exit 0
fi

echo "kernel:  $VENDOR $VERSION ($ABI)"
echo "dest:    $OUT"

download() {
  echo "fetching $1"
  curl -fSL --progress-bar --max-time 1800 -o "$OUT.part" "$1"
}

# Direct first, then through the mirror: the direct GitHub URL is not reliably
# reachable from mainland China, and this is a one-time 85 MB download.
download "$URL" || {
  echo "direct download failed, retrying via $MIRROR" >&2
  download "${MIRROR}${URL}"
}

# An HTML error page saved under an .apk name would fail at runtime in a way
# that is hard to trace, so check it is really a zip before keeping it.
if ! python3 -c "import sys,zipfile; sys.exit(0 if zipfile.is_zipfile(sys.argv[1]) else 1)" "$OUT.part" 2>/dev/null; then
  rm -f "$OUT.part"
  echo "downloaded file is not a valid APK" >&2
  exit 1
fi

mv "$OUT.part" "$OUT"
echo "done: $OUT ($(du -h "$OUT" | cut -f1))"
