# 发布与更新

App 不是从应用商店分发的，而是 APK 直装。这意味着**「用户怎么知道有新版本」这件事必须由项目自己解决**——本文就是这个问题的答案。

## 一、发布在哪里

**GitHub Releases 和 Gitee Releases 同时发布，互为镜像。**

| 平台 | 作用 |
|---|---|
| **GitHub** | 主仓库、CI 运行地、国外网络可直连 |
| **Gitee** | 国内访问快、下载稳，国内用户主要走这里 |

App 内的更新检查会**同时查询两边并取版本号更高的那个**，所以任何一边先发出去都能被用户收到；两边都发则是为了下载速度。

## 二、更新是怎么工作的

```
App 启动（或用户点「检查更新」）
   │
   ├─► GET https://api.github.com/repos/<owner>/<repo>/releases/latest
   └─► GET https://gitee.com/api/v5/repos/<owner>/<repo>/releases/latest
                │
                ▼
        比较 tag 与已安装版本（纯数字比较，1.10.0 > 1.9.0）
                │
                ▼
        下载 assets 里的 .apk → 交给系统安装器
```

关键约束：

- **仓库必须公开。** 私有仓库的 Release API 需要 token，而把 token 打进 App 等于公开泄露。
- **tag 必须是版本号**（`v1.1.0`）。App 靠 tag 判断版本，`nightly` 这类 tag 会被忽略。
- **Release 必须附带 `.apk` 附件**。没有附件的版本会被识别出来，但安装按钮不可用。
- 接口是匿名的，会受速率限制；App 因此**每次启动只查一次**，且失败时静默处理。

## 三、发一个版本（标准流程）

```bash
# 1. 改版本号：app/pubspec.yaml  →  version: 1.1.0+2
#    （+2 是 Android versionCode，必须递增，但不参与版本比较）

# 2. 写更新说明 —— 它会原样显示在 App 的「更新说明」里
#    用 annotated tag，注释就是 release notes

# 3. 提交并打 tag
git commit -am "release: 1.1.0"
git tag -a v1.1.0 -m "免密登录更稳

- 修复 dsh web 重启后偶发要求重新登录
- 设备列表支持拖动排序"

# 4. 推上去，剩下的交给 CI
./tools/push.sh
```

`tools/push.sh` 把当前分支和所有 tag 推到两个远端（Gitee 的 `origin` 和 GitHub 的
`github`），并在推之前**先比对最新 tag 与 `pubspec.yaml` 的版本号**——CI 的第一步就是
查这个，对不上会直接失败，所以在这里挡住能省一次来回。

```bash
./tools/push.sh --tags-only    # 只推 tag
./tools/push.sh --dry-run      # 只打印要执行的命令，不真的推
```

### 别再每次输密码

两个平台都不接受账号密码（GitHub 从 2021 年起就不支持了），要的是令牌。让 git 记住它：

```bash
git config --global credential.helper store
```

之后第一次输入会被记下来，以后不用再输。`store` 是**明文**存在 `~/.git-credentials`；
想更保守可以用 `cache`（只留在内存里，过一阵子忘掉），或者 `libsecret`（用桌面钥匙串）。

GitHub 的令牌需要 `repo` 和 **`workflow`** 两个 scope——只要推送里改了
`.github/workflows/` 下的文件，缺 `workflow` 就会被拒。

推送 tag 之后，`.github/workflows/release.yml` 会自动：

1. **校验 tag 与 `pubspec.yaml` 一致**（不一致直接失败，避免发出版本号对不上的包）；
2. `flutter analyze` + `flutter test`；
3. 构建 release APK（并用 `--dart-define` 把仓库地址编进包里）；
4. 在 GitHub 建 Release 并附上 APK 与更新说明；
5. 把 tag 推到 Gitee、建 Gitee Release、上传同一批 APK。

**每次发布出两个包**，名字里带不带 `legacy` 就是它们的区别：

| 附件名 | 内容 | 谁该装 |
|---|---|---|
| `dsh-mobile-client-<版本>.apk` | 普通版，复用手机上已装的更新内核 | 绝大多数人 |
| `dsh-mobile-client-<版本>-legacy.apk` | 内置 arm32 Chromium 113，32 位进程 | 系统 WebView 太旧、又装不了新内核的老机器 |

两个包都要传。App 内更新器**按文件名区分**二者并各取所需，不会把老设备更新到普通版，也不会让普通用户白下 120 MB。漏传某一个，那一半用户就收不到更新。

## 四、CI 需要的配置

在 GitHub 仓库的 **Settings → Secrets and variables → Actions** 里设置：

| 类型 | 名称 | 值 |
|---|---|---|
| Variable | `GITEE_REPO` | `你的用户名/dsh-mobile-client` |
| Secret | `GITEE_TOKEN` | Gitee 私人令牌，勾选 `projects` 权限 |
| Secret | `ANDROID_KEYSTORE_BASE64` | keystore 的 base64，一整行（见第六节） |
| Secret | `ANDROID_KEYSTORE_PASSWORD` | keystore 密码 |
| Secret | `ANDROID_KEY_ALIAS` | keystore 别名，脚本默认 `dsh-mobile-client` |
| Secret | `ANDROID_KEY_PASSWORD` | keystore 密码（同上） |

- **签名那四个不是可选项**：缺任何一个，工作流会在 `Set up release signing` 那一步直接失败。这是故意的——没有 keystore 就只能出 debug 签名的包，而那种包用户装不上去，发出去等于没发（原因见第六节）。
- **Gitee 不配置也能用**：那一步会被跳过，只发 GitHub；App 内更新仍可工作（会走 GitHub 那一边）。
- Gitee 免费版没有托管 Runner，所以是「GitHub 构建 → 镜像到 Gitee」，而不是各建各的。

## 五、手动兜底

CI 不可用时，本地构建后到两个平台手动建 Release：

```bash
cd app

# 普通版
flutter build apk --release --flavor standard \
  --dart-define=DSH_GITHUB_REPO=你的用户名/dsh-mobile-client \
  --dart-define=DSH_GITEE_REPO=你的用户名/dsh-mobile-client
# 产物：build/app/outputs/flutter-apk/app-standard-release.apk

# 内置内核版（先下载内核，约 85 MB）
../tools/fetch_webview_kernel.sh
flutter build apk --release --flavor legacy --target-platform android-arm \
  --dart-define=DSH_GITHUB_REPO=你的用户名/dsh-mobile-client \
  --dart-define=DSH_GITEE_REPO=你的用户名/dsh-mobile-client
# 产物：build/app/outputs/flutter-apk/app-legacy-release.apk
```

手动发布时的硬性要求：

- 先跑一次 `tools/setup-release-signing.sh`（它会写好 `app/android/key.properties`）。没有它，本地出的包是 debug 签名，用户装不上去；
- tag 用 `v1.1.0` 形式，**和 `pubspec.yaml` 的版本号一致**；
- 附件名以 `.apk` 结尾，两个包分别是 `dsh-mobile-client-1.1.0.apk` 和 `dsh-mobile-client-1.1.0-legacy.apk`；
- Gitee 的 Release 需要仓库在「设置 → 仓库信息」里允许发布 Release。

## 六、签名（重要，别跳过）

> **为什么这节不能跳。** 用 debug 签名发布，等于每个版本换一把钥匙：CI 每次都在全新
> 的 runner 上现场生成一把。Android 拒绝用不同密钥签名的包覆盖安装，用户点「更新」
> 只会看到「签名不同，请先卸载」——而卸载会把设备列表和存在系统 Keystore 里的访问密
> 码一起删掉。1.1.0 到 1.1.5 都是这么发出去的：v1.1.4 的证书指纹是 `52975f23…`，
> v1.1.5 是 `3f984c80…`，没有一把相同。

现在的机制（`app/android/app/build.gradle.kts`）：

- 有 `app/android/key.properties` → 用它指向的 keystore 签名；
- 没有 → 退回 debug 签名，并在 release 构建时打印一行警告；
- CI 里设了 `DSH_REQUIRE_RELEASE_SIGNING=true`，没有 keystore 就**直接构建失败**，不会再悄悄发一个装不上去的包。

### 一次性配置

```bash
sh tools/setup-release-signing.sh
```

脚本会生成 keystore（默认 `~/.config/dsh-mobile-client/release.jks`，在仓库外）、写好 `app/android/key.properties`，并打印要填进 GitHub Secrets 的四行值：

| Secret | 值 |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | 脚本打印的 base64（一整行） |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_ALIAS` | 默认 `dsh-mobile-client` |
| `ANDROID_KEY_PASSWORD` | 同 keystore 密码 |

这四行**只填在 GitHub**。签名是 APK 文件自身的属性，Gitee 只是托管 GitHub 已经签好名的同一批文件（见第三节的镜像步骤），它那边既不需要也没法重新签名。Gitee 自己要配的只有 `GITEE_TOKEN` 和「允许发布 Release」，与签名无关。

填好之后，CI 日志里会多出一步 `Verify the release signature`，打印证书指纹；和脚本打印的那行一致，就说明生效了。

### 三条铁律

1. **keystore 和密码各备份一份**（离线）。丢了就再也发不出能覆盖安装的包，只能让所有用户卸载重装一次；
2. **永远不要换 key**。换一次等于让所有老用户重装；
3. **不要提交进仓库**。`.gitignore` 已排除 `*.jks` / `*.keystore` / `key.properties`。

> 1.1.5 及以前的老用户，因为历史上每个版本签名都不同，升级到第一个固定签名的版本时仍然要卸载重装**一次**。为了不让这次卸载变成「包没了」，App 会把下载好的 APK 同时存一份到系统「下载」目录，并在发现签名不同时直接告诉用户去那里装；Android 10 以下没有免权限的公共目录，改为提供「分享安装包」按钮。逻辑在 `app/lib/core/state/update_controller.dart` 的 `_handToInstaller`。

## 七、更新说明怎么写

App 里「更新说明」显示的就是 Release 的 body，按纯文本渲染。建议：

```
一句话说清这个版本最重要的变化

- 具体改动一
- 具体改动二
```

不要用表格或嵌套列表——手机上不好读。

## 八、版本号规则

| 情况 | 怎么改 |
|---|---|
| 修 bug | `1.0.0` → `1.0.1` |
| 加功能 | `1.0.1` → `1.1.0` |
| 不兼容改动 | `1.1.0` → `2.0.0` |
| 预发布 | `1.2.0-beta.1`（排在 `1.2.0` 之前，不会推给正式用户） |

`pubspec.yaml` 里的 `+N` 是 build number，只影响 Android 的 versionCode，不参与比较，但**每次发版都要递增**。

## 九、发布后自检

1. `设置 → 更新 → 检查更新`，应显示「发现新版本」与正确版本号；
2. 点「下载并安装」，应能下载并唤起系统安装器；
3. 到 Gitee/GitHub 的 Releases 页面确认 APK 可下载；
4. 用旧版本设备验证一次真实的升级路径；
5. CI 日志里 `Verify the release signature` 打印的指纹和上一版**完全一致**。不一致说明 keystore 换了，用户会装不上。
