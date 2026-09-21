#!/usr/bin/env bash
#
# Generate the keystore this project signs its release APKs with, and print the
# four repository secrets the release workflow reads.
#
# Why this is not optional
# ------------------------
# Without a keystore the release build falls back to the debug key, and every
# machine — and every CI run — mints its own. An APK signed by a different key
# cannot be installed over an existing app: Android asks the user to uninstall
# first, which also throws away their device list and the access PIN held in the
# platform keystore. That is not hypothetical: it is how 1.1.0 through 1.1.5
# shipped.
#
# Run this once:
#
#   sh tools/setup-release-signing.sh
#
# Then add the four values it prints as repository secrets:
#   GitHub -> Settings -> Secrets and variables -> Actions -> New repository secret
# Gitee needs nothing: it only mirrors APKs GitHub has already signed.
#
# Keep the keystore AND the password. Losing them means no later release can be
# installed as an update by anyone who already has the app — the same uninstall
# dance, for every user, forever.

# Typing "sh tools/..." is natural, and on Ubuntu /bin/sh is dash, which has no
# read -s and no pipefail. Re-exec under bash instead.
if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

set -euo pipefail

cd "$(dirname "$0")/.."

KEYSTORE="${DSH_KEYSTORE:-$HOME/.config/dsh-mobile-client/release.jks}"
ALIAS="${DSH_KEY_ALIAS:-dsh-mobile-client}"

find_keytool() {
  if [ -n "${KEYTOOL:-}" ]; then echo "$KEYTOOL"; return; fi
  if command -v keytool >/dev/null 2>&1; then command -v keytool; return; fi
  # The repo keeps its own JDK for local builds; see docs/RELEASING.md.
  for candidate in .tooling/jdk21/bin/keytool "$HOME/.tooling/jdk21/bin/keytool"; do
    if [ -x "$candidate" ]; then echo "$candidate"; return; fi
  done
  echo ""
}

KEYTOOL="$(find_keytool)"
if [ -z "$KEYTOOL" ]; then
  echo "keytool not found. Install a JDK 17+ or set KEYTOOL=/path/to/keytool." >&2
  exit 1
fi

if [ -e "$KEYSTORE" ]; then
  echo "A keystore already exists at $KEYSTORE." >&2
  echo "Refusing to overwrite it: every installed copy is signed with it." >&2
  exit 1
fi

password="${DSH_KEYSTORE_PASSWORD:-}"
if [ -z "$password" ]; then
  read -rsp "Keystore password (leave empty to generate one): " password
  echo
fi
if [ -z "$password" ]; then
  password="$(openssl rand -hex 16 2>/dev/null || head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)"
fi

mkdir -p "$(dirname "$KEYSTORE")"

"$KEYTOOL" -genkeypair \
  -keystore "$KEYSTORE" \
  -storetype PKCS12 \
  -alias "$ALIAS" \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -storepass "$password" -keypass "$password" \
  -dname "CN=dsh-mobile-client, O=dsh-mobile-client, C=CN"

# java.util.Properties reads a backslash as an escape character, so a password
# containing one has to be doubled. The release workflow does the same.
escape() { printf '%s' "$1" | sed 's/\\/\\\\/g'; }

cat > app/android/key.properties <<EOF
storeFile=$KEYSTORE
storePassword=$(escape "$password")
keyAlias=$ALIAS
keyPassword=$(escape "$password")
EOF

echo
echo "Keystore: $KEYSTORE"
echo "Alias:    $ALIAS"
echo
echo "Fingerprint (the release log prints the same line):"
"$KEYTOOL" -list -keystore "$KEYSTORE" -storepass "$password" -alias "$ALIAS" | grep -E 'SHA256|SHA-256' || true
echo
echo "Add these four repository secrets:"
echo "  GitHub -> Settings -> Secrets and variables -> Actions -> New repository secret"
echo
echo "  ANDROID_KEYSTORE_BASE64"
base64 < "$KEYSTORE" | tr -d '\n'; echo
echo
echo "  ANDROID_KEYSTORE_PASSWORD"
echo "  $password"
echo
echo "  ANDROID_KEY_ALIAS"
echo "  $ALIAS"
echo
echo "  ANDROID_KEY_PASSWORD"
echo "  $password"
echo
echo "app/android/key.properties was written as well, so a local release build"
echo "is signed with the same key. It is git-ignored: never commit the keystore"
echo "or the password."
