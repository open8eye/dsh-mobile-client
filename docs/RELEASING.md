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
git push origin master --tags
```

推送 tag 之后，`.github/workflows/release.yml` 会自动：

1. **校验 tag 与 `pubspec.yaml` 一致**（不一致直接失败，避免发出版本号对不上的包）；
2. `flutter analyze` + `flutter test`；
3. 构建 release APK（并用 `--dart-define` 把仓库地址编进包里）；
4. 在 GitHub 建 Release 并附上 APK 与更新说明；
5. 把 tag 推到 Gitee、建 Gitee Release、上传同一个 APK。

## 四、CI 需要的配置

在 GitHub 仓库的 **Settings → Secrets and variables → Actions** 里设置：

| 类型 | 名称 | 值 |
|---|---|---|
| Variable | `GITEE_REPO` | `你的用户名/dsh-mobile-client` |
| Secret | `GITEE_TOKEN` | Gitee 私人令牌，勾选 `projects` 权限 |

- **不配置也能用**：Gitee 那一步会被跳过，只发 GitHub；App 内更新仍可工作（会走 GitHub 那一边）。
- Gitee 免费版没有托管 Runner，所以是「GitHub 构建 → 镜像到 Gitee」，而不是各建各的。

## 五、手动兜底

CI 不可用时，本地构建后到两个平台手动建 Release：

```bash
cd app
flutter build apk --release \
  --dart-define=DSH_GITHUB_REPO=你的用户名/dsh-mobile-client \
  --dart-define=DSH_GITEE_REPO=你的用户名/dsh-mobile-client
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

手动发布时的硬性要求：

- tag 用 `v1.1.0` 形式，**和 `pubspec.yaml` 的版本号一致**；
- 附件名以 `.apk` 结尾（建议 `dsh-mobile-client-1.1.0.apk`）；
- Gitee 的 Release 需要仓库在「设置 → 仓库信息」里允许发布 Release。

## 六、签名（重要，别跳过）

默认配置用 **debug 签名**，方便直接 `flutter build apk --release` 出包。但这有三个后果：

1. 换一台机器、换一个 `~/.android`，签名就变了；
2. **签名不同的包无法覆盖安装**，用户必须先卸载（会丢掉设备列表和密码）；
3. 无法上架任何应用商店。

正式发布请：

```kotlin
// app/android/app/build.gradle.kts
signingConfigs {
    create("release") {
        storeFile = file(System.getenv("DSH_KEYSTORE") ?: "release.jks")
        storePassword = System.getenv("DSH_STORE_PASSWORD")
        keyAlias = System.getenv("DSH_KEY_ALIAS")
        keyPassword = System.getenv("DSH_KEY_PASSWORD")
    }
}
buildTypes { release { signingConfig = signingConfigs.getByName("release") } }
```

keystore 放在仓库外（`.gitignore` 已排除 `*.jks` / `*.keystore`），CI 里用 base64 存进 Secret 再解码。

> **一旦用正式签名发布过，就再也不要换。** 换了等于让所有老用户重装。

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
4. 用旧版本设备验证一次真实的升级路径。
