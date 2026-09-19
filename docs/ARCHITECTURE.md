# 架构说明

> 面向想改这个项目的人。读完你会知道每一层为什么存在、改动会牵动哪里。

## 一、整体数据流

```
App (Flutter)
 ├─ features/home/home_shell.dart      四图标导航；持有「当前设备」与它的密码
 │   ├─ features/scanner               相机 → DshEndpoint
 │   ├─ features/browser/dsh_webview   WebView + JS 桥 + 自动重新登录
 │   ├─ features/devices               设备列表 / 增删改
 │   └─ features/settings              设置 / 桌宠 / 关于
 │
 ├─ core/state/*Controller             ChangeNotifier：设备、设置
 ├─ core/storage/*                      devices.json / settings.json / Keystore
 ├─ core/notifications/*                注入 JS + flutter_local_notifications
 └─ core/pet/pet_platform              MethodChannel → Android 悬浮窗服务
```

## 二、连接与认证

### 服务端事实（来自 dsh-pocket 与 dsh web）

| 事实 | 影响 |
|---|---|
| `dsh web` 监听 `127.0.0.1:3080`，根路径要求一次性 `?token=<启动token>` 换 cookie | 浏览器直连 3080 会 401；应走 3081 |
| `dsh-pocket` 在 `0.0.0.0:3081` 起认证代理，端口被占会顺延到 3082…3091 | **不要猜端口**，地址必须带端口 |
| 代理的登录 cookie = `sha256(PIN : sessionKey)`，`sessionKey` 是**进程级随机值** | `dsh web` 一重启，cookie 必失效 |
| 接受 `GET /?token=<PIN>`，命中即种新 cookie | 这是「自动重新登录」的全部基础 |
| 按 Host 分类：`loopback` / `lan`（含 CGNAT `100.64/10`）/ `public` | Tailscale 地址走**局域网**密码 |
| 连续输错 5 次锁 60 秒 | 自动重登**不能**盲目重试，必须失败即停 |

### App 侧策略（`dsh_webview.dart`）

1. 进入 URL 优先用 `authenticatedUrl(password)` → `http://host:port/?token=<PIN>`；
2. 页面加载完成后用 JS 探测登录表单（`input[name="token"]`）；
3. 命中且**本次会话还没用密码重试过** → 用保存的密码再进一次；
4. 仍然命中 → 弹出原生密码框（而不是让用户对着网页表单输）；
5. 用户输入后**存进 Keystore**，再进一次。

第 3 步的「一次」是刻意的：密码错了就停下来问人，
而不是无限重试把自己撞进 60 秒的限速里。

## 三、凭证存储

| 数据 | 位置 | 理由 |
|---|---|---|
| 访问密码 | `flutter_secure_storage`（Keystore / Keychain） | 敏感；且**写入失败不回退明文** |
| 设备列表 | `devices.json`（应用支持目录） | 便于备份、便于人工检查 |
| 设置 | `settings.json` | 同上 |
| 「是否设过密码」 | 设备记录里的一个布尔值 | 列表要显示锁图标，但不需要密码本身 |

`SecretStore.writePassword` 在密钥库拒绝写入时抛 `SecretStoreException`，
调用方把失败原样告诉用户。**这是刻意的**：把密码写进明文配置比丢掉它更糟。

## 四、通知转发

Android WebView **没有实现 Web Notifications API**，所以网页里 `new Notification(...)`
本来会静默失败。`web_notification_script.dart` 在 `AT_DOCUMENT_START` 注入一个替身：

- 覆盖 `window.Notification`，把 `(title, options)` 通过
  `window.flutter_inappwebview.callHandler('dshNotify', …)` 送到 Dart；
- 兜底再监听 `document.title` 变化（页面在后台时转发），覆盖我们没识别出的通知路径；
- 脚本幂等，重复注入不会叠加。

Dart 侧 `NotificationService.show` 用 `tag` 派生通知 id，让同一会话的更新**替换**而不是堆叠。

「仅后台时通知」由 `AppLifecycleObserver` 判断——用户正看着对话时不该被自己的手机弹窗打断。

## 五、桌面伙伴

```
Flutter (设置页开关)
   │ MethodChannel: com.dshmobile.dsh_mobile_client/pet
   ▼
MainActivity.configureFlutterEngine   → isSupported / hasOverlayPermission / show / hide
   ▼
PetOverlayService (前台服务, specialUse)
   ├─ WindowManager.addView(TYPE_APPLICATION_OVERLAY)
   └─ CompanionView.onDraw  ← 换角色只需要改这里
```

关键约束：

- 悬浮窗**必须**由前台服务持有，否则 App 一退到后台窗口就被回收；
- `SYSTEM_ALERT_WINDOW` 是特殊权限，只能跳系统页面申请，**没有回调**——
  所以 App 回到前台后需要重新检查（见 `settings_screen.dart` 的挂起逻辑）；
- iOS 无法覆盖系统 UI，`PetPlatform` 会直接返回「不支持」，UI 据此给出提示。

## 六、扩展点

| 想做的事 | 改哪里 |
|---|---|
| 换桌宠角色（Live2D / 精灵图） | `CompanionView.onDraw`（Android）+ `CompanionPainter`（预览） |
| 支持新的二维码内容 | `DshEndpoint.tryParse` |
| 新的通知来源 | `WebNotificationScript.source` + `_handleNotification` |
| 加语言 | `core/i18n/l10n.dart` 的 `_table` |
| 换存储后端（如 sqlite） | `core/storage/*`，控制器只依赖接口 |
