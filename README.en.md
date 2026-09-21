<h1 align="center">DSH Mobile Client</h1>

<p align="center">
  <strong>A phone app for the DeepSeek Harness already running on your computer: scan to connect, no password typing.</strong>
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

> **To be clear: there is no DSH inside this app.**
>
> It does **not** bundle DeepSeek Harness into the APK, and it does **not** run a copy of DSH on
> the phone. It is a **shell**: a WebView pointed at the DSH web page **already running on your
> computer**, plus the few things a browser cannot do (keep the access PIN in the platform
> keystore, manage several devices, turn page notifications into system notifications).
>
> Model calls, code execution, file access and session history all still happen **on your
> computer**. The phone is a remote control, not a host — if DSH is not running there, the app is
> a screen that cannot connect.
>
> In other words: DSH itself comes from the two upstream projects. This project only wraps it for
> the phone, and makes that wrapper better than a browser tab.

The desktop build already exposes DSH to a phone browser through its "Phone access" page.
A browser still makes that awkward:

| The annoyance | What this app does |
|---|---|
| Restarting `dsh web` on the computer invalidates the phone session, so the 8-character access PIN must be typed again | The PIN lives in the platform keystore (Android Keystore / iOS Keychain) and the app signs in again automatically — **you never type it twice** |
| Several computers, plus LAN / Tailscale / public entries, distinguishable only by bookmarks | A **device list**: scan to add, nickname, switch in one tap |
| Web notifications never reach the phone | Page notifications are **forwarded to real system notifications** |
| Open browser, find address, type password, every time | Open the app; it goes straight to the last device |
| Want some personality | A **desktop companion** that floats over the launcher (Android) — **on hold, see below** |

## Screenshots

Taken on a real Android device:

<p align="center">
  <img src="docs/images/screenshot-scan.jpg" width="200" alt="Scan to connect">
  <img src="docs/images/screenshot-devices.jpg" width="200" alt="Device list">
  <img src="docs/images/screenshot-home.jpg" width="200" alt="The DSH page once connected">
  <img src="docs/images/screenshot-settings.jpg" width="200" alt="Settings">
</p>

Left to right: scan to add a device → the device list (a device's LAN and Tailscale addresses) →
the DSH page on the computer, straight after connecting → Settings (theme, notification
forwarding, automatic re-login).

## Features

- **Scan to connect** — scan the QR code on the computer's Settings → Phone access page.
  Manual address entry works too, and a share link carrying `?token=` needs no PIN at all.
- **Device list** — multiple DSH servers; tap to switch, rename, edit or delete.
- **Nicknames** — each device has a name, shown in the middle of the bottom bar. Tap it to
  return to that device, long-press to edit it.
- **No first-run wizard** — DSH's setup dialog means nothing on a server that is already
  configured, so the app clicks through its own "skip all → start using" for you (can be turned
  off in Settings).
- **Two addresses per device** — store an alternate address (usually the Tailscale one)
  alongside the main one. Both are probed at connect time and the one that answers first is
  used: LAN at home, Tailscale elsewhere, with no manual switching.
- **Several devices at once** — each connected device keeps its session alive (up to four),
  so switching is instant: no reload, no logging in again.
- **Icon-only navigation** — Scan / Sessions / Device name / Devices / Settings / Refresh.
  The current device has no AppBar any more, so the page gets the whole screen.
- **Notification forwarding** — page notifications become phone notifications, with an
  "only while in background" option.
- **Automatic re-login** — the stored PIN is replayed whenever the session is rejected.
  This is the single biggest difference from using a browser.
- **Tailscale remote access** — reach the computer from anywhere (see below).
- ~~**Desktop companion**~~ — **on hold, not offered in the UI.** The code, the Android
  overlay service and the settings fields are all still here; only the entry point is
  hidden. Flip `PetFeature.available` in `app/lib/core/pet/pet_feature.dart` to bring it
  back. See [docs/DESKTOP-PET.md](docs/DESKTOP-PET.md).
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
3. The address is pre-filled — give the device a nickname. If the machine has another way in
   (its Tailscale address, say), put it in **Alternate address** and the app will pick
   whichever answers. Save;
4. When the page asks for the password, the app prompts for it — enter the **8-character PIN**
   shown on the computer;
5. From then on the app opens straight into DSH — **no more typing the PIN**.

> The add/edit form has **no password field**, and that is deliberate. The password is asked
> for at the moment you actually connect and the server actually asks — which is also the only
> moment a wrong PIN can be told from a right one. Typing it into the form first, and again
> when connecting, is the same job done twice.

### 4. Notifications and the companion

- **Notifications** are on by default; the app asks for the system permission on first use.
- **Companion**: on hold for now — the settings entry is hidden. See below.

## Tailscale remote access

To reach the computer over 4G without exposing DSH to the internet, Tailscale is the easy path:

1. Install Tailscale on both the computer and the phone, signed into the same account;
2. On the computer's Phone access page, pick the computer's Tailscale address
   (`100.x.y.z`) in the **"LAN address" dropdown** — dsh-pocket treats CGNAT
   `100.64.0.0/10` as LAN, so the **LAN PIN** applies, not the public one;
3. Connect the app to `http://100.x.y.z:3081` with that LAN PIN.

Traffic stays inside your tailnet and never touches a third-party public entry point.

> **Do not go through Tailscale at home.** Once step 2 points the "LAN address" at the
> Tailscale address, the QR code carries `100.x.y.z` — so at home, on the same Wi-Fi, the
> traffic still goes through Tailscale. No manual switching needed: set the main address to
> `http://192.168.x.x:3081` and the **alternate address** to `http://100.x.y.z:3081`. Both are
> probed at once and whichever answers first wins.
>
> **If it is always slow**, it is probably not getting a direct path and is relaying through
> Tailscale's DERP servers, which are all outside mainland China. Run
> `tailscale ping <phone>` on the computer: `direct` is good, `via DERP(...)` is the problem.
> Enabling UPnP / NAT-PMP on the router makes a direct path much more likely.

## Desktop companion

> **On hold.** Nothing was removed, but the settings entry is hidden while the feature is
> finished off. See `PetFeature.available`.

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

### Why the page goes blank, and the compatibility layer

The DSH frontend is built by Vite. Vite transpiles **syntax** down to its configured target and
does not polyfill **runtime APIs**, so the bundle carries both kinds of thing beyond an older
engine's reach:

| construct | needs Chromium |
|---|---|
| private methods `#name() {}` | 84 |
| `??=` / `\|\|=` / `&&=` | 85 |
| `static {}` blocks | **94** |

**Syntax is what actually blocks it, not APIs.** A parse error means **not one line of the file
runs**, so no shim can rescue it.

A diagnostic report from the field settled it: the Redmi K20 Pro's system WebView is **Chromium
83**, and the log read

```
uncaught: Uncaught SyntaxError: Unexpected token '=' @ .../assets/index-DS_0SByp.js:2:8267
```

That offset is exactly `p ??= H0(...)`. In the same report the shims had plainly worked
(`compat: SHIMMED Object.hasOwn, ...`) and the page was still white — because the script was never
parsed.

The app therefore does two things:

1. **Compatibility shims** injected ahead of the page's own scripts, filling in the runtime APIs
   the bundle actually uses (the list is the next section). They genuinely help on an old engine
   (syntax fine, APIs missing) and do nothing at all on a new one.
2. **A version gate**: below Chromium 94 the app shows an explanation instead of a white page. The
   floor is 94 (`static {}`) rather than 85 (`??=`) on purpose — patching the operators would only
   move the parse error a few kilobytes down the same file.

Below 94 the **only** fix is a newer kernel. Rewriting the bundle that far down is not a shim but a
transpiler — `static {}` cannot be rewritten textually without understanding the class it sits in.

### Parsing is not the same as working

A second field report came from the same user on the same phone, this time running the **bundled
kernel**:

```
webViewKernel: upgraded kernel: bundled webview/armeabi-v7a.apk (now 113.0.5672.136)
loaded http://100.111.56.77:3081/
```

Chromium 113 parsed the bundle and mounted the app, and it still could not connect:

```
Uncaught TypeError: Promise.withResolvers is not a function @ http://100.111.56.77:3081/:47:65
[session-controller] control stream failed: TypeError: AbortSignal.any is not a function
[connection] connection lost, retry #1
```

So **94 is the "can parse" floor, not the "can run" floor**. `Promise.withResolvers` needs 119 and
`AbortSignal.any` needs 116, both above 113 — and the second one lands on the very first read of
the session controller's control stream, so the UI appears and the connection never comes up.

With those two added, the full shim list is (every entry was **found by scanning the shipped
bundles**, not guessed):

| API | needs Chromium |
|---|---|
| `String.prototype.replaceAll` | 85 |
| `Array.prototype.at` / `String.prototype.at` | 92 |
| `crypto.randomUUID` | 92, **and a secure context** |
| `Object.hasOwn` | 93 |
| `Array.prototype.findLast` / `findLastIndex` | 97 |
| `AbortSignal.timeout` | 103 |
| `Array.prototype.toReversed` / `toSorted` / `with` | 110 |
| `String.prototype.toWellFormed` | 111 |
| `ArrayBuffer.prototype.transfer` | 114 |
| `AbortSignal.any` | 116 |
| `Object.groupBy` / `Map.groupBy` | 117 |
| `Promise.withResolvers` | 119 |
| `URL.canParse` | 120 |
| `Set.prototype.union` / `intersection` / `difference` | 122 |
| `URL.parse` | 126 |
| `Promise.try` | 128 |
| `Symbol.dispose` | 134 |
| `navigator.clipboard` | **a secure context** |

### Reusing a newer kernel already on the phone

Rather than asking the user to modify their system, the app tries to **reuse a newer WebView kernel
that is already installed**. This is built on
[WebViewUpgrade](https://github.com/JonaNorman/WebViewUpgrade) (MIT), which hooks the WebView
provider binders so that **this process** resolves its WebView from another installed package.

It **does not replace the system WebView, does not affect other apps, and needs no root**. The user
can undo it by uninstalling the kernel app.

Two constraints shape how it is implemented:

- **Timing.** The provider is bound the first time a WebView is created in the process and cannot be
  swapped afterwards. The logic therefore runs in `WebViewKernelProvider` — a `ContentProvider` —
  whose `onCreate` fires during `bindApplication`, strictly before `Application.onCreate`. That is
  the only window that is still early enough. Switching after a WebView already exists needs a cold
  start to take effect.
- **Only a monolithic kernel APK works.** The split APKs Google Play delivers for Chrome and Android
  System WebView **cannot** be used, so a store-installed Chrome will not be picked up even when it
  is new enough; a standalone APK is required.

When no usable kernel is found the app shows an explanation instead of a white page. A test guards
the Android-side `MIN_CHROMIUM` against drifting from the Dart-side
`CompatScript.minimumChromium`.

There are two traps pointing the other way: `crypto.randomUUID` and `navigator.clipboard` both
require a **secure context**, and this app deliberately talks to a LAN address over plain HTTP — so
they are missing even on the **newest** WebView. `crypto.getRandomValues` and
`document.execCommand('copy')` carry no such restriction, so they are shimmed as well.

Every shim checks for the native implementation first, so a current device is untouched. Their
behaviour is pinned down by `tools/compat_check.mjs`, which deletes the real implementation, puts
ours in its place and compares the results (`node tools/compat_check.mjs`, Node 24+, run in CI).

One thing is **deliberately not** shimmed: `structuredClone` is only reported in the log. A clone
that is subtly wrong corrupts state silently, while a missing method throws where the bug is — and
only the second one is debuggable from a phone.

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

> Release builds are signed with the keystore that `app/android/key.properties` points at;
> `sh tools/setup-release-signing.sh` generates it and writes that file. Without it the build
> falls back to the debug key, and **such an APK cannot be installed over an existing app**:
> Android refuses a package signed by a different key, so the user has to uninstall first and
> loses their device list and the access PIN held in the platform keystore. Configure it before
> distributing. The keystore lives outside the repository (`.gitignore` already excludes
> `*.jks`, `*.keystore` and `key.properties`); see `docs/RELEASING.md` section 6.

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
