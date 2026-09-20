# 桌面伙伴（桌宠）设计与升级路径

> **当前状态：暂缓。** 代码全部保留、仍然参与编译和分析，只是设置页不再显示入口。
> 开关在 `app/lib/core/pet/pet_feature.dart` 的 `PetFeature.available`；
> 升级时若用户之前开着桌宠，`main.dart` 会主动关掉它，免得留下一个关不掉的悬浮窗。
> 本文是设计文档，内容依然有效。

## 一、平台现实

先把最难听的话说在前面：

| 平台 | 系统级悬浮 | 说明 |
|---|---|---|
| **Android** | ✅ 可以 | `SYSTEM_ALERT_WINDOW` + `TYPE_APPLICATION_OVERLAY` + 前台服务 |
| **iOS** | ❌ 不可以 | 系统不允许任何第三方 App 覆盖桌面或其他 App。没有越狱、没有私有 API 就是做不到 |

所以本项目的桌宠是 **Android 特性**；iOS 只提供应用内的角色展示。
任何声称 iOS 能悬浮桌宠的方案，要么用了私有 API（上不了架），要么是在骗你。

## 二、当前实现

```
设置页开关
   │  PetPlatform.show(scale, opacity, imagePath)
   ▼
MainActivity  MethodChannel  "com.dshmobile.dsh_mobile_client/pet"
   ▼
PetOverlayService  (前台服务, foregroundServiceType=specialUse)
   ├─ WindowManager.addView(CompanionView, TYPE_APPLICATION_OVERLAY)
   ├─ 拖动（DragListener，位移小于 12px 视为点击）
   └─ 点按 → 打开 MainActivity
```

角色有两种来源：

1. **内置角色** —— `CompanionView.onDraw` 用 Canvas 画的矢量小生物
   （呼吸式上下浮动 + 眨眼 + 腮红 + 投影），
   Flutter 侧 `CompanionPainter` 画的是同一套图形，所以设置页预览与实际一致；
2. **用户图片** —— 设置里选一张图，会被**复制到应用数据目录**再使用
   （image_picker 返回的是系统缓存路径，系统随时可能清掉）。

## 三、升级成真正的动漫角色

### 方案 A：精灵图 / 序列帧（最简单）

替换 `CompanionView.onDraw` 里的绘制逻辑，用 `BitmapFactory` 解码一张精灵图，
按时间切换帧。适合「几张 PNG 拼出来的 Q 版角色」。

改动量：**只改 `CompanionView`**。服务、权限、Channel、Flutter 侧全都不动。

### 方案 B：Live2D（效果最好，成本最高）

Live2D Cubism SDK for Native / Java 需要在 Android 侧做渲染。
建议做法：

1. 在 `app/android` 里接入 Cubism SDK；
2. 让 `CompanionView` 持有一个 `LAppModel`，在 `onDraw`（或独立的 GLSurfaceView）里渲染；
3. 触摸事件转发给模型的命中判定，做「摸头 / 说话」等交互；
4. Flutter 侧把 `CompanionPainter` 换成静态预览图即可。

注意事项：

- Cubism SDK 有自己的授权条款（个人 / 小规模免费，商用需确认），
  **不要**把模型文件提交进本仓库，让用户自己放；
- 悬浮窗里的 OpenGL 渲染在部分国产 ROM 上可能被限制，建议提供「回退到图片模式」。

### 方案 C：Flutter 直接渲染

如果你不需要覆盖桌面，只在 App 内展示角色，那么完全可以留在 Flutter：
用 `CustomPainter`、`Rive`、`lottie` 或 Flutter 版 Live2D 播放器。
这条路 **iOS 也能用**。

## 四、已知限制

- **Android 14+** 启动前台服务要求 App 处于前台。当前实现是用户在设置页点开关时启动，
  满足这个条件；如果你要做「开机自动显示桌宠」，需要额外处理（且各 ROM 行为不同）。
- **国产 ROM 的省电策略**可能杀掉前台服务。可在设置页引导用户加白名单
  （`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`），当前版本还没做。
- **悬浮窗权限没有回调**，授权后需要 App 回到前台重新检查一次。
  当前实现依赖用户再点一次开关。
- 桌宠**不参与业务逻辑**：它不显示会话进度、不响应 agent 状态。
  如果要做「有状态的桌宠」（比如跑任务时变成工作中），
  需要把 WebView 的会话状态通过 `PetPlatform` 推给服务。
