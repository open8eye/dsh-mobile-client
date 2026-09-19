# DSH Remote 项目总结（含可迁移经验）

> **文档定位**：本文既是本项目的技术总结，也是一份**可迁移到其他项目**的参考——
> 抽取了通用问题模型、可复用的架构模式与技巧、以及踩坑清单。
>
> **基线**：仓库 commit `5977159`；补丁相关结论在 DSH `0.1.6-alpha.2` 上实测。

---

## 一、一句话概括

把一台电脑上**只监听 `127.0.0.1` 的本地 Web 服务**，通过「密码认证代理 + 免费隧道」
安全地暴露给手机；客户端只做三件事：**自动带凭证、自动发现隧道、全屏显示官方 UI**。

**产物规模（实测）**：Release APK **18.7 KB**，仓库 340 KB，三端代码约 2,070 行。

---

## 二、问题模型（可迁移）

「让手机访问电脑上的本地服务」这类需求，普遍要翻过三道坎：

| # | 障碍 | 本项目表现 |
|---|---|---|
| 1 | 服务只绑 loopback | DSH 官方禁止绑 `0.0.0.0`（RCE 风险），只听 `127.0.0.1:3080` |
| 2 | 家庭网络无公网 IP | 用 cloudflared quick tunnel，域名每次重启都变 |
| 3 | 服务把远程当"低权限" | DSH 把 `settings`/`credentials` 锁 loopback，远程访问时 UI 降级 |

**第 3 条最容易被忽略、也最费时间**：症状不是"连不上"，而是"连上了但按钮不出现"。

---

## 三、架构与数据流

```
DSH Remote (Android WebView / PWA)
   │  ① 自动携带 Basic Auth（Keystore 解密 / 页面内存）
   │  ② DoH 查 CNAME → 得到当前 *.trycloudflare.com → 直连
   ▼
cloudflared quick tunnel
   ▼
0.0.0.0:8082   插件内嵌认证代理（server/plugin/lib/proxy.js）
   │  ③ 密码校验（timingSafeEqual + 失败限速）
   │  ④ Host/Origin 改写为 127.0.0.1:3080   ← 破解障碍 3 的关键
   │  ⑤ 注入移动 CSS / viewport meta / WS token 脚本
   ▼
127.0.0.1:3080  dsh web（官方 UI）
```

---

## 四、关键设计决策：把每一层都外包

这是项目能做到 2,000 行的根本原因。

| 本该自己写 | 这里的做法 | 代价 |
|---|---|---|
| 聊天 UI | 复用官方 Web UI，只注入 378 行 CSS | 依赖对方 DOM 结构 |
| HTTP 反向代理 | `node:http` 裸管道 | 需自己处理 gzip / 错误 |
| WebSocket 转发 | `net.connect` + 手拼握手行 | 需自己处理认证头缺失 |
| 用户体系 | Basic Auth 一行 | 无多租户、无纵深防御 |
| NAT 穿透 + TLS | `spawn(cloudflared)` | 依赖第三方隧道 |
| CI / 分发 / 托管 | GitHub Actions + Pages | 无自有域名 |

**可迁移判断**：如果被适配的服务有稳定 Web UI，**注入适配层 ≫ 重写 UI**。
本项目两条路都走过——曾自研移动 UI，后废弃（`proxy.js` 注释：
「自研移动 UI 已废弃，官方 UI + 适配 CSS 方案」）。

---

## 五、七个可复用的具体技巧

### 1. loopback 伪装：破解"远程降级"

代理把 `Host`/`Origin` 改写成上游 loopback 形式：

```js
host: `127.0.0.1:${upstreamPort}`,
...(req.headers.origin ? { origin: `http://127.0.0.1:${upstreamPort}` } : {}),
```

一举两得：**特权功能解锁** + **隧道域名变化无需通知上游**。
前提：认证必须成为唯一且可靠的边界（见第七节风险 2）。

### 2. DoH 隧道发现：让"随机域名"变"固定域名"

用阿里 DoH 查固定域名的 CNAME/TXT，从应答里抠出真实隧道主机名：

```java
URL u = new URL("https://dns.alidns.com/resolve?name=" + q + "&type=TXT");
// 取 type==5(CNAME) 或 16(TXT) 且含 trycloudflare.com 的 data
```

**关键洞察**：不要跟随 CNAME 去访问固定域名（Quick Tunnel 证书只覆盖
`*.trycloudflare.com`，必然 TLS 不匹配），而是**直接连隧道主机名**。

### 3. WS 认证 cookie 引导：解决浏览器不带 Basic Auth

浏览器 WebSocket 握手**不发送** Basic Auth 头。解法：页面注入脚本 fetch 一个
带认证的 token 端点，种下 HttpOnly cookie，WS 握手自动携带：

```js
fetch("/__dsh_ws_token", { credentials: "include" })
```

注意：此机制存在竞态（见第七节风险 4）。

### 4. 凭证加密存储：Keystore + 失败不回退明文

`CredentialStore.java` 是全项目质量最高的部分：AES-GCM + Android Keystore(TEE)，
含旧版明文自动迁移，且**加密失败宁可存空也不留明文**：

```java
String encPass = CredentialStore.encrypt(finalPass);
// 加密失败存空串（下次重填），绝不回退明文
prefs.edit().putString(KEY_PASS, encPass == null ? "" : encPass).apply();
```

这个"失败不回退"的决策值得直接照搬。

### 5. 幂等注入

所有 HTML 注入先检查标记，避免重复注入：

```js
if (!html.includes('<style data-dsh-mobile-remote>')) { /* 注入 */ }
```

### 6. 单实例 Mutex + 双端口看门狗

`start-dsh.ps1` 用命名 Mutex 防重复启动；每 10 秒**同时**检查两个端口
（`3080` 服务本身 + `8082` 内嵌代理）——只查前者会漏掉
"插件加载失败导致代理静默消失"这种故障。

### 7. 零依赖 Android 客户端

`app/build.gradle` **没有任何 `implementation`**，且
`MainActivity extends android.app.Activity`（非 `AppCompatActivity`），
所以连 AndroidX 都不引入。配合纯矢量自适应图标（无 PNG 密度桶，
`minSdk 26` 恰好是 adaptive icon 下限）+ 仅 v2 签名，得到 18.7 KB APK。

---

## 六、度量基线

| 指标 | 实测值 | 说明 |
|---|---|---|
| Release APK | 18,724 B | 仅 8 个 zip 条目 |
| `classes.dex` | 15,572 B | 全部业务逻辑 |
| 仓库（不含 .git） | 340 KB | |
| 代码行数 | app 477 / pwa 481 / server 1110 | |
| Android 依赖 | 0 | |
| 插件依赖 | 2（`zod`、`qrcode-terminal`） | |
| 签名方案 | 仅 v2 | minSdk 26 使 v1 非必需，省掉 META-INF |

---

## 七、已知问题与教训

### 🔴 迁移时务必避免

**1. 补丁寄生在对方源码的具体代码行上**

`apply-isloopback-patch.ps1` 靠精确字符串替换改 DSH 的 `client.js`。
实测在 DSH `0.1.6-alpha.2` 上**已双重失效**：

- **路径错**：脚本找 `profiles/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-client-connection/...`，
  但 pnpm 已把依赖提升到 `profiles/node_modules/@deepseek-ai/dsh-client-connection/...`
- **字符串错**：实际行是
  `isLoopback: transport?.ownsHost === true || pageLocation === void 0 || ...`，
  脚本的 `$old` 缺少 `transport?.ownsHost === true || ` 前缀

> **教训**：能用"协议层改写"（如技巧 1 的 Host 伪装）解决的，绝不用"源码打补丁"。
> 若必须打补丁，用正则/glob 而非精确串，并让失败保持"响亮"（本项目这点做对了）。

**2. 信任了客户端可控的 Header 做限速**

```js
return req.headers['cf-connecting-ip'] || req.socket.remoteAddress || 'unknown'
```

`cf-connecting-ip` 由客户端可控。代理监听 `0.0.0.0`，局域网内伪造该头
即可让指数退避完全失效。

> **教训**：限速的 IP 来源必须是**连接层**事实，不能是应用层 Header——
> 除非能确认连接确实来自可信代理。

### 🟠 功能性缺陷

**3. PWA 的密码框是装饰性的**：`settings.pass` 赋值后**再无引用**（已 grep 验证）。
真实认证靠 `window.open` 弹窗让用户手输 + `setTimeout(..., 3000)` 后强关——
用户来不及输完，且弹窗可能被拦截。
→ **教训**：UI 收集了但从不使用的输入，比没有更糟。

**4. WS cookie 引导有竞态**：注入的 `fetch` 与前端建立 WS 并行，
cookie 未种下时 WS 返回 401 → 实时数据缺失，正是该机制想修的问题。应加重试/等待。

**5. 双 gzip 隐患**：代理无条件对 json/text 再 gzip，但把客户端
`accept-encoding` 原样转发上游。DSH `compression` 默认 `'none'` 所以当前安全，
一旦上游开启 gzip 就会压两层。
→ **教训**：压缩判断要检查 `upRes.headers['content-encoding']`。

### 🟡 工程细节

6. **Android `versionCode` 恒为 1**：比"签名每次不同"更硬的问题——
   Android 要求 `versionCode` 递增才能覆盖安装。
7. **文档引用了不存在的文件**：`MAINTENANCE.md` 被引用 5 处
   （`proxy.js`、`cordis.patch.yml`、`start-dsh.ps1`），但该文件未入库，
   所有排查线索失效。
8. **死代码与矛盾注释**：`TRUSTED_HOST = 'dsh.remote'` 仅定义未使用，
   且与同文件注释、`cordis.patch.yml` 的 `trustedHosts` 三处说法互相矛盾。
9. **CI 把 keystore 当 artifact 上传**：公开仓库任何人可下载；且每次都是新密钥，
   注释"keep for future updates"不成立。
10. **配置默认值不一致**：`cordis.patch.yml` 的 `tunnelEnabled: false` 与
    `index.js` 默认 `true` 不一致，不走 bundle patch 安装会起两条隧道冲突。

---

## 八、迁移到新项目的检查清单

- [ ] 被适配服务是否有稳定 Web UI？有 → 优先注入适配层，别重写
- [ ] 服务是否只绑 loopback？→ 需要代理层；优先 Host/Origin 改写而非源码补丁
- [ ] 认证是否成为唯一边界？→ 必须补限速，且限速 IP 取连接层
- [ ] 隧道域名是否变化？→ DoH 发现，且**直连隧道主机名**而非固定域名
- [ ] 是否需要 WebSocket？→ 浏览器 WS 不带 Basic Auth，需 cookie 引导（记得处理竞态）
- [ ] 客户端凭证是否落盘？→ Keystore/Keychain 加密，且失败不回退明文
- [ ] `versionCode` 是否有递增策略？
- [ ] 引用的文档是否都真的在仓库里？
- [ ] 压缩/缓存策略是否与上游冲突？

---

## 九、什么情况下不要照搬

- **服务本身支持多用户/多租户** → Basic Auth 单密码模型不适用
- **服务已有官方移动端** → 直接用，别套壳
- **需要离线可用** → 本方案是纯在线壳，断网即不可用
- **对方 Web UI 结构频繁变动** → 注入适配层的维护成本会超过重写
