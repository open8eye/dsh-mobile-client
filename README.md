<h1 align="center">DSH Mobile Client</h1>

<p align="center">
  <strong>把电脑上的 DeepSeek Harness 装进手机：一个 App、扫码即连、长期免密。</strong>
</p>

<p align="center">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-blue.svg"></a>
  <img alt="Platform" src="https://img.shields.io/badge/platform-Android%20%7C%20iOS-lightgrey.svg">
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.35-02569B.svg">
</p>

<p align="center">
  简体中文 · <a href="README.en.md">English</a>
</p>

---

## 这是什么

**DSH Mobile Client** 是 [Open DeepSeek Harness Desktop](https://github.com/flaqai/open-deepseek-harness-desktop)
（社区桌面版）与 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的**移动端客户端**。

桌面版自带的「手机访问」已经能把 DSH 暴露给手机浏览器，但用浏览器访问始终有几处不顺手：

| 浏览器访问的不便 | 本 App 的做法 |
|---|---|
| 电脑上 `dsh web` 一重启，手机上就要**重新输一次 8 位访问密码** | 密码存进系统密钥库（Android Keystore / iOS Keychain），App 自动重新登录，**不用再输** |
| 多台电脑 / 局域网 + Tailscale + 公网多个入口，只能靠书签分辨 | **设备列表**：扫码添加、自定义昵称、一键切换 |
| 网页通知在手机上收不到 | 网页里的通知**冒泡成手机系统通知** |
| 每次都要打开浏览器、找地址、输密码 | 打开 App 直接进入上次的设备 |
| 想有点个性 | **桌面伙伴**：动漫角色悬浮在手机桌面上（Android） |

## 功能

- **扫一扫连接** — 扫描电脑上「设置 → 手机访问」页面的二维码即可添加设备。
  也支持手动填写地址，以及直接扫描带 `?token=` 的分享链接（这种链接连密码都不用输）。
- **设备列表** — 支持多台 DSH；点击即切换，可重命名、改地址、删除。
- **设备昵称** — 每台设备都能取名字，昵称直接显示在底部导航栏上。
- **四个图标导航栏** — 扫一扫 / 当前设备 / 设备列表 / 设置。
- **通知转发** — 把网页通知变成手机通知；可选择「仅后台时通知」，正在用 App 时不打扰。
- **自动重新登录** — 保存的密码会在会话失效时自动重放，这是本 App 相对浏览器最大的差别。
- **Tailscale 远程访问** — 出门在外也能连回家里电脑（见下文）。
- **桌面伙伴** — Android 上可以把角色悬浮在桌面（需要悬浮窗权限）；iOS 系统不允许第三方 App 覆盖桌面，因此只有应用内展示。
- **自动更新** — 应用内检查 GitHub / Gitee 上的新版本，直接下载并调起系统安装器（见 [docs/RELEASING.md](docs/RELEASING.md)）。

## 工作原理

```
┌──────────────────────────────┐
│  DSH Mobile Client (本 App)  │
│                              │
│  ① 扫码得到 http://IP:3081   │
│  ② 密码存进 Keystore         │
│  ③ 连接时用 ?token=<密码>    │
│     重新登录（免手输）        │
│  ④ WebView 持久化会话 cookie │
└───────────────┬──────────────┘
                │  http(s)://<地址>:3081
                ▼
┌──────────────────────────────┐
│  dsh-pocket 认证代理 (:3081) │
│  · 按 Host 区分公网/局域网密码│
│  · 校验通过 → 种 30 天 cookie │
│  · Host/Origin 改写为 loopback│
│  · 注入 dsh web 启动 token    │
└───────────────┬──────────────┘
                ▼
┌──────────────────────────────┐
│  dsh web (127.0.0.1:3080)    │
│  官方 Web UI + 移动端布局适配 │
└──────────────────────────────┘
```

### 关键点：为什么 App 能做到「不用再输密码」

DSH 的网页会话是一个 cookie，而 `dsh-pocket` 把它的有效性**绑定到电脑上 `dsh web` 进程**：
进程一重启，旧 cookie 立刻失效，浏览器只会再把登录页摆到你面前。

App 的做法是**把密码留在手机的系统密钥库里**，并且每次连接都从
`/?token=<密码>` 这个入口进——服务端接受这个参数后会立刻种一个全新的 cookie。
于是「重启后要重新登录」这件事对用户不再可见：App 自己完成了一次登录，你只是打开了 App。

> 这也是本项目选择「套壳 + 注入适配层」而不是重写 UI 的原因：
> 官方 Web UI 才是功能最全、更新最快的那个界面。

## 快速开始

### 1. 电脑端准备

1. 安装并打开 **Open DeepSeek Harness Desktop**；
2. 确认插件 **`dsh-pocket`** 已安装（桌面版通常已内置）；
3. 打开 **设置 → 手机访问**，你会看到两个二维码：
   - **📶 局域网**：手机和电脑在同一个 Wi-Fi（或同一个 Tailscale 网络）时使用；
   - **🌐 公网**：点了「开启公网访问」之后出现，人在外面也能用。

> 建议在手机访问页面里把局域网密码**自定义成固定的 8 位密码**，
> 这样密码不会变，App 可以一直用它自动登录。

### 2. 安装 App

从 [Releases](../../releases) 下载 APK 安装，或者按下面的「构建」自行编译。

### 3. 扫码连接

1. 打开 App → 底部导航栏点 **扫一扫**；
2. 扫描电脑上「手机访问」页面的**局域网二维码**；
3. App 会预填地址，**把「访问密码」填成电脑上显示的那 8 位**，保存；
4. 之后每次打开 App 都会直接进入 DSH —— **不再需要输入密码**。

### 4. 通知与桌面伙伴

- **通知**：默认开启。首次打开会请求系统通知权限；网页里的通知会变成手机通知。
- **桌面伙伴**：设置 → 桌面伙伴 → 打开开关，会引导你去授予「显示在其他应用上层」权限。

## Tailscale 远程访问

想在 4G 下连回家里电脑，又不想把 DSH 暴露到公网，**Tailscale 是最省事的方案**：

1. 电脑和手机都装上 Tailscale 并登录同一个账号；
2. 在电脑上「手机访问」页面的**「局域网地址」下拉框**里，选中电脑的 Tailscale 地址
   （形如 `100.x.y.z`）——dsh-pocket 会把 CGNAT `100.64.0.0/10` 视为局域网，
   所以这里用的仍然是**局域网密码**，而不是公网密码；
3. 手机上用 App 连接 `http://100.x.y.z:3081`，密码填局域网密码。

这样流量只走你的 tailnet，不经过任何第三方公网入口。

> 注意：`100.64.0.0/10` 是 CGNAT 网段，手机必须真的在同一个 tailnet 里才连得上。

## 桌面伙伴

| 平台 | 能力 |
|---|---|
| **Android** | 角色可以悬浮在桌面 / 其他 App 之上，可拖动、点按回到 App；可换自己的角色图片。需要 `SYSTEM_ALERT_WINDOW` 权限。 |
| **iOS** | **系统不允许**第三方 App 覆盖桌面，因此只有应用内的角色展示（设置页预览）。这是平台限制，不是本项目偷懒。 |

内置角色由 Flutter（`CompanionPainter`）和 Android（`CompanionView`）分别绘制同一套图形，
所以设置页的预览和桌面上的样子是一致的。

**想换成真正的动漫角色？** 现在的结构是为此留的：

- 现在：内置矢量角色，或用户在设置里选一张自己的图片；
- 之后：把 `CompanionView.onDraw` 换成 Live2D / 精灵图渲染即可，
  服务、权限、MethodChannel 都不用动。详见 [docs/DESKTOP-PET.md](docs/DESKTOP-PET.md)。

## 技术栈与选型

**Flutter 3.35（Dart 3.9）**，一套代码同时出 Android 和 iOS。

选它的理由：

1. **需求 7 决定了必须是「一套代码 + 原生扩展」**：桌面伙伴只能靠 Android 原生
   悬浮窗（`TYPE_APPLICATION_OVERLAY` + 前台服务）实现，Flutter 通过一个
   MethodChannel 调它；如果为了这一件事拆成两套原生代码，前 6 条需求就要写两遍。
2. **角色可以是一个 Flutter Widget**：桌宠未来要动画、要 Live2D、要交互，
   Flutter 的渲染管线比「原生 + WebView」更好扩展。
3. **生态正好覆盖全部需求**：`flutter_inappwebview`（JS 注入 / Cookie）、
   `mobile_scanner`（扫码）、`flutter_local_notifications`（通知）、
   `flutter_secure_storage`（Keystore / Keychain）。

> 如果你只想要一个**几十 KB 的纯 WebView 壳**，可以参考
> [dsh-mobile-app](https://github.com/hongshuxifan321/dsh-mobile-app)（Android 原生，零依赖）。
> 本项目要的是「一个真正的 App」，所以选了 Flutter。

## 更新与发布

App 是 APK 直装、不走应用商店，所以「用户怎么知道有新版本」必须由项目自己解决：

| 环节 | 做法 |
|---|---|
| **发布** | GitHub Releases 与 Gitee Releases 同时发布，互为镜像 |
| **检查** | App 同时查询两边的公开 Release API，取版本号更高的那个 |
| **安装** | 下载 APK 后交给系统安装器，需要用户授予一次「安装未知应用」 |

打一个 tag 就会自动走完整个流程：

```bash
# 1. 改 app/pubspec.yaml 的 version: 1.1.0+2
# 2. 提交后打 tag，注释就是 App 里显示的「更新说明」
git tag -a v1.1.0 -m "免密登录更稳

- 修复 dsh web 重启后偶发要求重新登录"
git push origin master --tags
```

CI 会校验 tag 与 `pubspec.yaml` 是否一致、跑分析和测试、构建 APK、发 GitHub Release，再把同一个包镜像到 Gitee。

完整流程（Gitee 令牌配置、签名要求、版本号规则、手动兜底）见 **[docs/RELEASING.md](docs/RELEASING.md)**。

> ⚠️ 两个前提：仓库必须**公开**（私有仓库的 Release API 需要 token，而 token 不能打进 App）；
> 版本号必须**和 tag 一致**，否则 CI 直接失败——发出版本号对不上的包会让所有人的更新检查失灵。
>
> 如果你 fork 到自己账号下，构建时指定仓库地址：
> `--dart-define=DSH_GITHUB_REPO=you/dsh-mobile-client --dart-define=DSH_GITEE_REPO=you/dsh-mobile-client`

## 遇到白屏或连不上怎么办

这个 App **没有埋点、没有崩溃上报**，所以出问题时唯一的办法就是你把诊断信息发出来——那里面有定位所需的一切。

| 情况 | 怎么办 |
|---|---|
| **连不上** | 页面不再白屏，而是直接说明原因（超时 / 网络不通 / 服务器拒绝 / 页面空白），并给出对应建议。点「复制诊断信息」即可 |
| **平时** | `设置 → 诊断与反馈`：看日志、复制、分享，或直接跳到 GitHub Issues |

报告包含：设备型号、Android 与 **MIUI 版本**、**系统 WebView 的包名与版本**、当前设备地址、页面探测结果、本次与上一次运行的日志，以及页面里捕获到的 JS 异常和 `console.error`。

> 🔒 **访问密码和会话 Cookie 会被自动隐藏。** `?token=` 的值一律替换为 `<hidden>`；密码本身还会作为「已知密钥」被全文擦除，所以即使它出现在页面标题或报错信息里也留不下来。这不是可选项——擦除发生在日志写入时，调用方无法忘记。
>
> 这也是为什么白屏值得单独处理：它是唯一一种「页面加载成功了、但什么都没显示」的故障，没有错误码、没有异常，用户手上没有任何可反馈的东西。

### 白屏的根因与兼容层

DSH 的前端由 Vite 构建。Vite 会把**语法**降级到目标浏览器，但**不会 polyfill 运行时 API**——而它的包里用了 `Object.hasOwn`（需要 Chromium 93）和 `Array.prototype.at`（需要 Chromium 92）。

关键在于 `Object.hasOwn` 的每一处调用都在**引导整个应用的依赖注入容器**里。在 Chromium < 93 的 WebView 上它是 `undefined`，容器在装配自己时就抛 `TypeError`，React 永远挂不上，页面一片白——**没有错误码，没有异常，什么都没有**。这类 WebView 在旧机型上很常见（Android 10 / MIUI 12 等）。

App 因此在页面脚本之前注入一层兼容 shim，补齐这几个 API，并记录**哪些是被补上的**。报告里出现 `compat: SHIMMED Object.hasOwn, ...`，就说明该升级系统 WebView 了。

还有一个方向相反的坑：`crypto.randomUUID` 要求**安全上下文**，而本 App 是刻意用明文 HTTP 连局域网地址的——所以它在**最新**的 WebView 上同样不存在。`crypto.getRandomValues` 没有这个限制，于是也被一并补上。

每个 shim 都先检测原生实现，新设备上完全不生效；并且与原生实现做过逐项差分对比。

## 构建

### 本地构建

需要：Flutter 3.35+、Android SDK（compileSdk 36）、JDK 17–23（Gradle 8.12 不支持 JDK 24+）。

```bash
cd app
flutter pub get
flutter analyze
flutter build apk --release     # 产物：app/build/app/outputs/flutter-apk/app-release.apk
```

iOS 需要 macOS + Xcode：

```bash
cd app
flutter build ios --release
```

> 默认的 release 构建使用 debug 签名，方便直接 `flutter build apk --release`。
> **正式分发前请换成你自己的签名**：在 `app/android/app/build.gradle.kts` 里配置
> `signingConfigs`，并把 keystore 放在仓库外（`.gitignore` 已排除 `*.jks` / `*.keystore`）。

### 应用图标

图标（Android 自适应图标 + iOS AppIcon）是脚本画出来的，不提交无法编辑的二进制：

```bash
python3 tools/generate_icons.py   # 需要 Pillow
```

改颜色或比例就改脚本里的常量，然后重跑；Android 的 legacy PNG、自适应前景、
`mipmap-anydpi-v26/ic_launcher.xml` 与 iOS 全部尺寸会一起更新。

### 构建注意事项

- 部分插件（如 `flutter_inappwebview_android`）会把自己的 `compileSdk` 锁在旧版本，
  在只装了新平台 SDK 的机器上会报 `Failed to find Platform SDK with path: platforms;android-34`。
  `app/android/build.gradle.kts` 已把所有子项目统一抬到 36，无需手动装旧 SDK。
- Gradle 8.12 不支持 JDK 24 及以上，请用 JDK 17–23。
- 首次构建需要下载 Gradle 与依赖，耗时较长；之后是增量构建。

## 项目结构

```
app/lib/
├── main.dart                      # 初始化服务、注入依赖
├── app.dart                       # 主题 / 语言 / 根路由
├── core/
│   ├── dsh/dsh_endpoint.dart      # 地址解析、Host 分类、token 提取
│   ├── models/                    # 设备与设置的数据模型
│   ├── storage/                   # JSON 文档 + 系统密钥库
│   ├── notifications/             # 通知服务 + 注入网页的 JS 桥
│   ├── browser/compat_script.dart # 注入页面的兼容 shim（旧 WebView 白屏的根因）
│   ├── diagnostics/               # 日志、脱敏、页面探测、反馈报告
│   ├── update/                    # 版本比较、GitHub/Gitee 查询、APK 下载
│   ├── platform/app_platform.dart # 系统设置页 / 安装 APK 的 MethodChannel
│   ├── pet/pet_platform.dart      # 悬浮窗 MethodChannel
│   ├── state/                     # ChangeNotifier 控制器
│   └── i18n/l10n.dart             # 中英文字符串表
└── features/
    ├── home/home_shell.dart       # 四图标底部导航
    ├── scanner/                   # 扫一扫
    ├── devices/                   # 设备列表 / 增删改
    ├── browser/dsh_webview.dart   # WebView 外壳 + 自动重新登录
    ├── settings/                  # 设置
    └── pet/                       # 角色绘制（与 Android 端一致）
```

## 安全与隐私

- **访问密码只存在系统密钥库**（Android Keystore / iOS Keychain），
  不写进普通配置文件；密钥库写入失败时**宁可报错也不回退明文**。
- 设备列表里**只保存「是否设置过密码」这个布尔值**，密码本身从不进内存缓存。
- App **不收集、不上传任何数据**，没有账号体系，没有统计埋点。
- 局域网明文 HTTP 是必要的（家用服务器没有证书），Android 侧已用
  `network_security_config` 说明原因；公网隧道始终是 HTTPS。
- DSH 能执行你电脑上的代码。**不要把二维码、地址或密码发给别人**；
  密码一旦泄露，请在电脑上「手机访问」页面点「刷新」换新。

## 致谢

本项目的每一块难啃的骨头都属于下面这些项目。**没有它们就没有这个 App。**

- **[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)**（deepseek-ai）——
  智能体运行时与 Web 工作区。本 App 显示的就是它的官方 Web UI。
- **[Open DeepSeek Harness Desktop](https://github.com/flaqai/open-deepseek-harness-desktop)**（flaqai）——
  开箱即用的社区桌面发行版。它提供的「手机访问」能力正是本 App 对接的对象，
  本项目也是因它而起。
- **[dsh-pocket](https://github.com/shaobeichen/dsh-pocket)**（shaobeichen）——
  手机访问代理：二维码、访问密码、局域网开关、cloudflared 隧道、移动端布局适配。
  本 App 的自动重新登录正是建立在它的 `?token=` 语义之上。
- **[dsh-mobile-app / DSH Remote](https://github.com/hongshuxifan321/dsh-mobile-app)**（hongshuxifan321）——
  把「手机壳 + 扫码连接 + 凭证加密存储」这条路走通的先行项目，
  本项目的许多设计取舍（尤其是凭证加密「失败不回退明文」）直接受益于它的总结，
  该总结收录于 [docs/REFERENCE-dsh-remote.md](docs/REFERENCE-dsh-remote.md)。
- **[dsh-web-mobile](https://github.com/mexiaosqwq/dsh-web-mobile)**（mexiaosqwq，MIT）——
  移动端布局适配，经 dsh-pocket 移植。
- **[cloudflared](https://github.com/cloudflare/cloudflared)** —— 公网隧道。

同时感谢 Flutter、以及 `flutter_inappwebview`、`mobile_scanner`、
`flutter_local_notifications`、`flutter_secure_storage`、`provider` 等开源项目的作者。

## 开源声明

- 本项目以 **MIT 许可证**开源，见 [LICENSE](LICENSE)。你可以自由使用、修改、分发。
- 本项目**不包含、不修改、不重新分发** DeepSeek Harness、Open DeepSeek Harness Desktop
  或 dsh-pocket 的代码；它只在运行时通过 HTTP/WebSocket 访问它们。
- 这些上游项目各自遵循其原有许可证：DeepSeek Harness 与 dsh-pocket（**GPL-2.0**）等，
  请以各自仓库为准。
- 本项目是**社区项目，与 DeepSeek 官方无关**。

## 路线图

- [x] 扫码 / 手动添加设备、设备列表与昵称
- [x] 凭证加密存储 + 自动重新登录
- [x] 网页通知 → 手机通知
- [x] Android 悬浮桌宠（内置角色 / 自定义图片）
- [ ] 桌宠：Live2D / 精灵图角色、点击互动、待机动作
- [ ] 连接状态与流式输出进度的常驻通知
- [x] 应用内检查更新 + 一键下载安装（GitHub / Gitee 双源）
- [ ] 多设备会话快速切换（同时保持后台连接）
- [ ] 桌面版「手机访问」页直接生成 App 深链二维码（省掉手输密码）
