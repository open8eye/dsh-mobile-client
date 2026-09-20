<h1 align="center">DSH Mobile Client</h1>

<p align="center">
  <strong>Your computer's DeepSeek Harness, in your pocket: one app, scan to connect, no password typing.</strong>
</p>

<p align="center">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-blue.svg"></a>
  <img alt="Platform" src="https://img.shields.io/badge/platform-Android%20%7C%20iOS-lightgrey.svg">
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.35-02569B.svg">
</p>

<p align="center">
  <a href="README.md">简体中文</a> · English
</p>

---

## What this is

**DSH Mobile Client** is a mobile client for
[Open DeepSeek Harness Desktop](https://github.com/flaqai/open-deepseek-harness-desktop) and
[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness).

The desktop build already exposes DSH to a phone browser through its "Phone access" page.
A browser still makes that awkward:

| The annoyance | What this app does |
|---|---|
| Restarting `dsh web` on the computer invalidates the phone session, so the 8-character access PIN must be typed again | The PIN lives in the platform keystore (Android Keystore / iOS Keychain) and the app signs in again automatically — **you never type it twice** |
| Several computers, plus LAN / Tailscale / public entries, distinguishable only by bookmarks | A **device list**: scan to add, nickname, switch in one tap |
| Web notifications never reach the phone | Page notifications are **forwarded to real system notifications** |
| Open browser, find address, type password, every time | Open the app; it goes straight to the last device |
| Want some personality | A **desktop companion** that floats over the launcher (Android) |

## Features

- **Scan to connect** — scan the QR code on the computer's Settings → Phone access page.
  Manual address entry works too, and a share link carrying `?token=` needs no PIN at all.
- **Device list** — multiple DSH servers; tap to switch, rename, edit or delete.
- **Nicknames** — each device has a name, shown right in the bottom navigation bar.
- **Four-icon navigation** — Scan / Current device / Devices / Settings.
- **Notification forwarding** — page notifications become phone notifications, with an
  "only while in background" option.
- **Automatic re-login** — the stored PIN is replayed whenever the session is rejected.
  This is the single biggest difference from using a browser.
- **Tailscale remote access** — reach the computer from anywhere (see below).
- **Desktop companion** — on Android the character floats over the launcher
  (needs the overlay permission). iOS forbids third-party overlays, so there it is in-app only.
- **In-app updates** — checks GitHub and Gitee for a newer release, downloads it and hands
  it to the system installer (see [docs/RELEASING.md](docs/RELEASING.md)).

## How it works

```
┌──────────────────────────────┐
│  DSH Mobile Client (this)    │
│  ① QR code → http://IP:3081  │
│  ② PIN stored in Keystore    │
│  ③ connect via ?token=<PIN>  │
│     (re-login, no typing)    │
│  ④ WebView keeps the cookie  │
└───────────────┬──────────────┘
                │  http(s)://<address>:3081
                ▼
┌──────────────────────────────┐
│  dsh-pocket auth proxy :3081 │
│  · LAN vs public PIN by Host │
│  · on success → 30-day cookie│
│  · rewrites Host/Origin      │
│  · injects the dsh web token │
└───────────────┬──────────────┘
                ▼
┌──────────────────────────────┐
│  dsh web (127.0.0.1:3080)    │
│  official Web UI + mobile CSS│
└──────────────────────────────┘
```

### The key trick: why the PIN is never asked twice

A DSH browser session is a cookie, and `dsh-pocket` binds that cookie's validity to the
`dsh web` **process** on the computer. Restart the process and the cookie is dead; a browser
can only show you the login form again.

This app keeps the PIN in the platform keystore and always enters through
`/?token=<PIN>`, which the server answers by minting a fresh cookie. The re-login becomes
invisible: the app performs it, you just open the app.

> This is also why the project wraps and injects into the official UI rather than rewriting it:
> the official Web UI is the most complete and the most current.

## Getting started

### 1. On the computer

1. Install and open **Open DeepSeek Harness Desktop**;
2. Make sure the **`dsh-pocket`** plugin is installed (the desktop build usually bundles it);
3. Open **Settings → Phone access**. You will see two QR codes:
   - **📶 LAN** — for a phone on the same Wi-Fi (or the same Tailscale network);
   - **🌐 Public** — appears after you enable public access; works from anywhere.

> Set the LAN PIN to a **fixed custom 8-character PIN**. Then it never changes and the app
> can keep using it to sign in automatically.

### 2. Install the app

Download the APK from [Releases](../../releases), or build it yourself (see below).

### 3. Scan and connect

1. Open the app, tap **Scan** in the bottom bar;
2. Scan the **LAN QR code** on the Phone access page;
3. The address is pre-filled — enter the **8-character access PIN** shown on the computer and save;
4. From then on the app opens straight into DSH — **no more typing the PIN**.

### 4. Notifications and the companion

- **Notifications** are on by default; the app asks for the system permission on first use.
- **Companion**: Settings → Companion → enable, then grant "display over other apps".

## Tailscale remote access

To reach the computer over 4G without exposing DSH to the internet, Tailscale is the easy path:

1. Install Tailscale on both the computer and the phone, signed into the same account;
2. On the computer's Phone access page, pick the computer's Tailscale address
   (`100.x.y.z`) in the **"LAN address" dropdown** — dsh-pocket treats CGNAT
   `100.64.0.0/10` as LAN, so the **LAN PIN** applies, not the public one;
3. Connect the app to `http://100.x.y.z:3081` with that LAN PIN.

Traffic stays inside your tailnet and never touches a third-party public entry point.

## Desktop companion

| Platform | Capability |
|---|---|
| **Android** | The character floats above the launcher and other apps, can be dragged, and tapping it returns to the app. A custom character image is supported. Requires `SYSTEM_ALERT_WINDOW`. |
| **iOS** | **The system does not allow** a third-party app to draw over the launcher, so only the in-app character (the preview in Settings) exists. That is a platform limit, not an omission. |

The built-in character is drawn twice — by Flutter (`CompanionPainter`) and by Android
(`CompanionView`) — so the Settings preview matches what floats on the home screen.

**Want a real anime character?** The structure is already prepared for it: replace
`CompanionView.onDraw` with a Live2D or sprite-sheet renderer; the service, the permission
and the MethodChannel stay unchanged. See [docs/DESKTOP-PET.md](docs/DESKTOP-PET.md).

## Tech stack

**Flutter 3.35 (Dart 3.9)** — one codebase for Android and iOS.

Why Flutter:

1. **The companion requirement forces "one codebase plus a native extension"**: a floating
   character needs an Android native overlay (`TYPE_APPLICATION_OVERLAY` plus a foreground
   service), reached through one MethodChannel. Splitting into two native codebases would mean
   writing the other six requirements twice.
2. **The character can be a Flutter widget**, which is a much better place for the animation,
   Live2D and interaction work that comes next.
3. **The ecosystem covers every requirement**: `flutter_inappwebview` (JS injection, cookies),
   `mobile_scanner`, `flutter_local_notifications`, `flutter_secure_storage`.

> If all you want is a **tiny WebView shell**, see
> [dsh-mobile-app](https://github.com/hongshuxifan321/dsh-mobile-app) (native Android, zero
> dependencies). This project wanted to be a real app, so it chose Flutter.

## Updates and releases

The app is installed as a plain APK, with no store in the loop, so "how does an installed copy
learn about a newer one" is the project's own problem:

| Step | How |
|---|---|
| **Publish** | GitHub Releases and Gitee Releases, mirrored |
| **Check** | The app queries both public release APIs and takes the higher version |
| **Install** | The APK is downloaded and handed to the system installer, which needs a one-time "install unknown apps" grant |

Pushing a tag runs the whole thing:

```bash
# 1. bump version: in app/pubspec.yaml  ->  1.1.0+2
# 2. commit, then tag; the tag annotation becomes the in-app release notes
git tag -a v1.1.0 -m "More reliable auto-login

- fixed a spurious re-login after dsh web restarts"
git push origin master --tags
```

CI checks the tag against `pubspec.yaml`, runs analyze and the tests, builds the APK, publishes
the GitHub release and mirrors the same file to Gitee.

The full procedure — Gitee token setup, signing requirements, version rules, manual fallback —
is in **[docs/RELEASING.md](docs/RELEASING.md)**.

> Two preconditions: the repository must be **public** (a private one needs a token for the
> release API, and a token cannot ship inside the app), and the tag must **match the version**,
> or CI fails outright — publishing a mismatched version breaks update checks for everyone.
>
> Forking under your own account? Point the build at it with
> `--dart-define=DSH_GITHUB_REPO=you/dsh-mobile-client --dart-define=DSH_GITEE_REPO=you/dsh-mobile-client`.

## When a page is blank or a device will not connect

This app has **no analytics and no crash reporting**, so when something breaks the only way
forward is for you to send the diagnostics — everything needed to pin it down is in there.

| Situation | What to do |
|---|---|
| **Cannot connect** | The page no longer goes blank; it names the cause (timeout / unreachable / refused / blank page) and suggests what to try. Tap "Copy diagnostics" |
| **Any other time** | `Settings → Diagnostics`: read the log, copy it, share it, or jump straight to GitHub Issues |

The report contains the device model, Android and **MIUI** versions, the **system WebView package
and version**, the current device address, the page probe result, this run's and the previous
run's logs, and any JavaScript exception or `console.error` captured from the page.

> 🔒 **The access password and session cookie are removed automatically.** Every `?token=` value
> becomes `<hidden>`, and the PIN itself is erased as a known secret wherever it appears — even
> inside a page title or an error message. This is not optional: scrubbing happens where the log
> is written, so a caller cannot forget it.
>
> It is also why the blank page deserved its own handling — it is the one failure where the page
> loads successfully and paints nothing, with no error code and no exception, leaving the user
> nothing at all to report.

## Building

Requires Flutter 3.35+, the Android SDK (compileSdk 36) and JDK 17–23
(Gradle 8.12 does not support JDK 24+).

```bash
cd app
flutter pub get
flutter analyze
flutter build apk --release     # app/build/app/outputs/flutter-apk/app-release.apk
```

iOS needs macOS and Xcode:

```bash
cd app
flutter build ios --release
```

> Release builds are signed with the debug key so that `flutter build apk --release` works out
> of the box. **Configure your own signing before distributing**: add a `signingConfigs` block in
> `app/android/app/build.gradle.kts` and keep the keystore outside the repository
> (`.gitignore` already excludes `*.jks` and `*.keystore`).

## Security and privacy

- **Access PINs live only in the platform keystore**, never in a plain configuration file.
  When the keystore rejects a write the app **reports the failure instead of falling back to
  cleartext**.
- The device list stores only the boolean "a PIN is set"; the PIN itself is never cached in memory.
- The app **collects and uploads nothing**: no account, no telemetry.
- Plain HTTP on the LAN is unavoidable (a home server has no certificate for a private address);
  the Android `network_security_config` documents exactly why. The public tunnel is always HTTPS.
- DSH can execute code on your computer. **Never share the QR code, the address or the PIN.**
  If a PIN leaks, press "refresh" on the Phone access page to rotate it.

## Credits

Every hard part of this project belongs to the projects below. **None of this exists without them.**

- **[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)** (deepseek-ai) —
  the agent runtime and Web workspace; this app displays its official Web UI.
- **[Open DeepSeek Harness Desktop](https://github.com/flaqai/open-deepseek-harness-desktop)** (flaqai) —
  the community desktop distribution. Its "Phone access" capability is exactly what this app
  talks to, and it is the reason this project exists.
- **[dsh-pocket](https://github.com/shaobeichen/dsh-pocket)** (shaobeichen) —
  the phone access proxy: QR codes, access PIN, LAN switch, cloudflared tunnel and mobile
  layout adaptation. The automatic re-login is built on its `?token=` semantics.
- **[dsh-mobile-app / DSH Remote](https://github.com/hongshuxifan321/dsh-mobile-app)** (hongshuxifan321) —
  the prior art that proved out "phone shell + scan to connect + encrypted credentials", and
  whose write-up directly shaped this project's decisions (notably never falling back to a
  cleartext credential). That write-up is kept at
  [docs/REFERENCE-dsh-remote.md](docs/REFERENCE-dsh-remote.md).
- **[dsh-web-mobile](https://github.com/mexiaosqwq/dsh-web-mobile)** (mexiaosqwq, MIT) —
  the mobile layout adaptation, carried over by dsh-pocket.
- **[cloudflared](https://github.com/cloudflare/cloudflared)** — the public tunnel.

Thanks also to Flutter and to the authors of `flutter_inappwebview`, `mobile_scanner`,
`flutter_local_notifications`, `flutter_secure_storage` and `provider`.

## Open source

- Released under the **MIT licence**, see [LICENSE](LICENSE). Use, modify and distribute freely.
- This project **does not include, modify or redistribute** the code of DeepSeek Harness,
  Open DeepSeek Harness Desktop or dsh-pocket. It only talks to them over HTTP/WebSocket at runtime.
- Those upstream projects keep their own licences: DeepSeek Harness and dsh-pocket (**GPL-2.0**)
  among them. Always check their repositories.
- This is a **community project and is not affiliated with DeepSeek**.
