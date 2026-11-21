# 32 · DeepSeek Plus 0.8 合并设计与动效

> 本文记录 **DeepSeek Plus 0.8** 相对上游 Simple Chat 1.2.3 的全部改动：身份、图标、
> 本地用户资料、致谢，以及全应用动效体系、思考强度滑块、语音频谱、引用预览卡、
> 图片缩放。逐版本的面向用户变更见 [`10-CHANGELOG.md`](10-CHANGELOG.md)。

## 32.1 来源与许可

| 来源 | 版本 | 许可 | 用了什么 |
|---|---|---|---|
| [Simple Chat](https://github.com/Pokanshuu/Simple-Chat) | 1.2.3 | MIT | **应用底座**：功能、架构与全部业务代码 |
| [DeepSeek App Replica](https://github.com/LiJiaHua1024/deepseek-app-replica) | 0.7.1 | GPL-3.0 | 视觉与交互参考（圆角几何、动效节奏、组件取舍） |

视觉部分按**净室**方式实现：只借鉴观感与结论（例如用户气泡 22/22/4/22 的角、
面板展开 260ms / 收起 180ms），代码由本仓库独立编写，不复制 Replica 的 TS / Java 源码。
唯一例外是应用图标——官方鲸鱼矢量，判断与风险见 §32.2。

## 32.2 身份

| 项 | 值 | 说明 |
|---|---|---|
| 显示名 | `DeepSeek Plus` | `strings.xml` 的 `app_name`，英文同值 |
| `applicationId` | `com.deepseek.plus` | debug 构建再带 `.debug` 后缀 |
| `namespace` | `com.simplechat.app` | 刻意不动 |
| 版本 | `0.8`（`versionCode = 44`） | |
| 产物名 | `DeepSeekPlus-0.8-debug.apk` / `-release.apk` | |
| User-Agent | `DeepSeekPlus/0.8 (Android)` | 仍从 `BuildConfig.VERSION_NAME` 取 |

`namespace` 不动是有意的：它决定 73 个源文件的包声明、`proguard-rules.pro` 的全限定名，
以及 Room 的 schema 导出路径（`app/schemas/com.simplechat.app.AppDatabase/`）。
改 `applicationId` 只影响安装身份与数据目录，改 `namespace` 则要动整棵树。

**换包名 = 另一个 App**：旧安装不会升级，数据不迁移，API Key 跨 UID 解不开
（Keystore 按 UID 隔离）。升级路径只有「旧版导出备份 → 卸载 → 装 0.8 → 导入」。
详见 [`03-代码框架.md`](03-代码框架.md) §30.2。

### 图标

自适应图标：白色背景 + `app/src/main/res/drawable/launcher_whale.xml`。
矢量取自官方鲸鱼：108dp 画布、`viewportWidth/Height = 50`、
`<group pivotX/pivotY=25 scaleX/scaleY=0.58>`、`fillColor = #426EFE`。
`minSdk 26` 只走 `mipmap-anydpi-v26/`，因此原先五档 `ic_launcher_foreground.png`
与浅灰 `ic_launcher_background.xml` 已删除。

> **已知的许可风险**：鲸鱼图形属于 DeepSeek 的品牌资产。本仓库为个人使用，
> 接受该风险并在关于页与本文标注来源；如需商用应换成自有图形。

## 32.3 相对上游的差异

| 改动 | 内容 |
|---|---|
| 移除更新检查 | 上游 GitHub release 检查在 0.8 上永远报「有新版本」（版本号远低于 tag）。`net/UpdateChecker.kt` 保留但无引用，关于页删掉「检查更新」行 |
| 关于页 | 新增「应用」行；项目地址改为 https://github.com/HuangM0405/deepseek-replica-plus ；新增「致谢」分组与许可条目 |
| 本地用户 | 头像 + 名字，仅存本机（§32.8） |
| 图片查看 | 双指缩放、双击 2.5×、放大后单指平移（§32.7） |
| 引用 | 点正文角标弹单条预览卡（§32.6） |
| 语音 | 按住说话显示真实 FFT 频谱（§32.5） |
| 滑块 | 胶囊渐变 + 星光（§32.4） |
| 动效 | 全应用三类节奏（§32.9） |

## 32.4 思考强度滑块

### 几何

| 项 | 值 |
|---|---|
| 轨道高 | 30dp，圆角 = 半高（胶囊） |
| 旋钮 | 40dp 正圆，按下 1.12× |
| 总高 | 48dp |
| 填充 | 水平线性渐变 `#3D5BFF → #6C5CE7 → #A886FF` |

轨道左右各内缩半个旋钮，保证旋钮在两端时完整落在轨道内。

### 星光

`ui/common/SliderStarField.kt`：固定种子生成一串星点，绘制时只取前 N 颗。

| 项 | 值 |
|---|---|
| 数量 | 由轨道宽度定基数（每 10dp 一颗，钳制 16..40），再乘档位亮度系数（低档 35% 起） |
| 单颗半径 | 0.6..1.7dp，随闪烁涨落 |
| 亮度 | 0.55..1，正弦闪烁，周期 2400..5200ms |
| 范围 | 只画在填充段内（`insideCapsule` 圆角判内） |

档位联动三个量：**数量**（35% → 100%）、**速度**（0.55× → 1.9×）、**亮度**（0.55 → 1.0）。
速度用「累计时间 × 倍率」推进，而不是拿时间戳乘倍率，所以换档时相位连续、不会集体跳相；
密度是同一串随机点的前缀，换档只增减尾部的点，已有星点不移位。

### 手势

- 按下**不吸附**到最近档，旋钮立刻跟手；只有提交的值吸附（`snapToIntervals`）。
- 松手当帧把落点写进 `settledFraction`，归位弹簧从那里起步——不会先画一帧旧值。
- 手势循环包在 `try/finally` 里：被父级滚动抢走指针也会复位，旋钮不会卡住。
- 连续档位（`intervals = 0`）不吸附。

### 性能

单层 Canvas、最多 32 颗星、每帧 32 次 `drawCircle`；时间值只在绘制闭包里读，
不触发重组；帧循环只在有星光时运行；单帧推进上限 48ms（切回前台不瞬移）。

`sparkIntensity = 0` 时不画星光——字体大小、温度这类滑块因此是纯渐变轨道。

## 32.5 语音频谱

`ui/chat/VoiceSpectrum.kt`：

| 项 | 值 |
|---|---|
| 采样 | 16 kHz、单声道 |
| 变换 | 512 点 radix-2 迭代 FFT，预计算旋转因子 |
| 窗 | Blackman，按本帧**真实样本数**铺满后补零（窗不随帧长截断，避免泄漏） |
| 分频 | 100–4000 Hz 对数分频，48 根柱 |
| 幅度 | 每段取 `hypot` 峰值 → dB → 4·log2(中心频率/1kHz) 补偿 → 归一化到 -60..-25 dB |
| 平滑 | 邻柱 (左 + 2·当前 + 右)/4；快攻慢放（衰减保留 0.55） |

分析在 IO 线程做，结果切回主线程写入 `VoiceInputController.spectrum`；
`VoiceComposer` 的 Canvas 按 48 根柱、2dp 描边绘制，没有真实频谱时退回固定形状。

## 32.6 引用预览卡

点正文里的 `[ⁿ]` 角标 → 底部弹出该条来源：站点图标、站点名、编号、标题、
摘要、页面时效、「打开网页」。遮罩点击、下滑退出或按返回键关闭；多来源仍走
`SourceSheet`。

## 32.7 图片查看

| 手势 | 行为 |
|---|---|
| 双指 | 缩放 1×–4×，以两指中心为焦点 |
| 双击 | 1× ↔ 2.5× |
| 放大后单指 | 平移（受 `clampViewerOffset` 限制在图像边界内） |
| 单击 | 未放大时关闭 |
| 翻页 | 放大时禁用 `HorizontalPager` 滑动，避免与平移抢手势 |

`clampViewerOffset(offset, scale, container, image)` 是纯函数，单测覆盖宽、高、方、零尺寸。

## 32.8 本地用户资料

| 项 | 值 |
|---|---|
| 存储 | DataStore：`local_user_name`、`local_user_avatar`（头像存文件路径） |
| 头像文件 | `files/profile/avatar-<时间戳>.png`，最长边 256px |
| 处理 | 2 的幂 `inSampleSize` 降采样 → EXIF 旋转/镜像 → 居中方形裁剪 → PNG |
| 名字 | 去首尾空白、最多 40 字 |
| 入口 | 设置 → 账户 → 本地用户；抽屉底部显示头像与名字 |

只存本机，不上传，也不进入备份的账号字段。

## 32.9 动效体系

### 三类节奏

| 场景 | 进入 | 退出 | 曲线 |
|---|---|---|---|
| 底部卡片（引用卡、来源面板、编辑弹层） | 260ms 上滑 | 180ms 下滑 | `PopupEasing` = cubic-bezier(0.23, 1, 0.32, 1) |
| 居中弹窗 | 200ms + 缩放 0.96→1 | 150ms | 同上 |
| 行内元素（来源条、选择头、加载环、语音提示） | 180ms 淡入 + 展开 | 140ms | 同上 |
| 页面切换 | 300ms 整屏推 | 同 | `FastOutSlowInEasing` |

`PopupEasing` 前段极快、尾段极缓，读起来是「弹出来然后停稳」，比标准 ease-out 更有手感。

### 弹层契约（`ui/common/PopupMotion.kt`）

```kotlin
val motion = rememberPopupMotion(visible, onDismissed = onDismiss)
Dialog(onDismissRequest = { visible = false }) {
    Modifier.popupModalLayer(motion.progress)   // 或 popupSheetLayer { 高度 }
    Modifier.popupScrimLayer(motion.progress)
    DialogDim(motion.progress)                  // 平台 dim 跟着卡片一起亮
}
```

三条不能违反的约定：

1. **退场由弹层自己管**：`onDismissRequest` 只置 `visible = false`，退场播完
   `rememberPopupMotion` 才回调父级 `onDismissed`。父级继续用 `if (data != null)` 控制挂载，
   否则节点被当场摘掉，退出动画根本没有机会播。
2. **进度只在绘制阶段读**：在 `graphicsLayer` / Canvas 闭包里读 `progress.value`，
   不触发重组。每帧重组一个 20dp 的卡片没关系，每帧重组整页就是卡顿。
3. **平台 dim 必须接进来**：`Dialog` 默认 dim 由系统一次性置 0.6，卡片却还在缩放入场，
   观感是「卡片很柔、背后那片黑啪一下出现」。`DialogDim` 找到 `DialogWindowProvider`
   的 window，把 `dimAmount` 从 0 跟到 0.6。

**减弱动态**：`rememberReduceMotion()` 读 `ValueAnimator.areAnimatorsEnabled()`，在
`ON_RESUME` 重读，经 `LocalReduceMotion` 提供给全应用。开启时所有弹层 `snapTo` 到终态，
不播动画。

### 覆盖范围

13 处 `Dialog`（文本输入、确认、预设编辑、许可、选项、导入模式、分享选项、编辑消息、
引用卡、来源面板、图片查看器……）、抽屉选择头与底部操作栏、输入面板、输入栏编辑横幅、
来源条、加载环、语音浮层提示。

### 输入面板与键盘（本版最容易翻车的一处）

- 面板在输入栏**下方**，展开时输入栏上移；`composer` 高度 = 输入栏 + 面板 + `imePadding`。
- 展开/收起用显式 `tween(260/180)`，**不用** `AnimatedVisibility` 的默认 spring：
  弹簧尾巴长，卡片早已淡出、空间还在慢慢收，读起来就是「顿一下」。
- 收起路径不再调用 `dismissInput()`：否则会把用户刚唤起的输入法又按下去。
- 点输入框让面板让位时，**不要**瞬间摘掉面板：`composer` 会先掉一个面板高度（约 200dp）
  再被键盘顶回来，这正是「窗口上下调整」。让 180ms 的收缩与键盘升起重叠、互相抵消。
- 输入栏阴影与面板同长（`SheetEnterMs` / `SheetExitMs`），两块阴影不会一前一后交接。

## 32.10 构建与门禁

```bash
cd DeepSeek-Plus-0.8
./gradlew.bat :app:assembleDebug :app:testDebugUnitTest :app:lintDebug :app:assembleRelease
```

| 项 | 最近一次（提交 `85ed445`） |
|---|---|
| 单元测试 | 832 通过 / 10 跳过 / 0 失败 |
| Lint | 0 error / 135 warning / 12 hint（与上游基线持平） |
| debug APK | `app/build/outputs/apk/debug/DeepSeekPlus-0.8-debug.apk`（约 20.3 MB） |
| release APK | `app/build/outputs/apk/release/DeepSeekPlus-0.8-release.apk`（约 4.6 MB，R8；无 keystore 时回退 debug 签名） |

本机注意项（与上游相同，另加一条）：

- 工程路径含非 ASCII 字符（`工作文件夹`）时，`gradle.properties` 需要
  `android.overridePathCheck=true`，否则 AGP 9 直接拒绝配置。
- Gradle 发行版走腾讯镜像可绕开 `services.gradle.org` 超时。
- `JAVA_HOME` = JDK 21，`sdk.dir` 写在 `local.properties`（不入库）。

## 32.11 未做与后续

- **不做内置浏览器**：来源一律交给系统浏览器（`SourceSheet` 的设计取舍见
  [`02-UI设计.md`](02-UI设计.md) 与上游 §25）。
- **无正式 keystore**：release 目前回退 debug 签名，正式分发前需生成并保管密钥。
- **无真机自动化**：本机未装模拟器镜像，验收以编译 + 单元测试 + lint + 用户真机反馈为准。
- **面板让位键盘**：若真机上仍有下坠感，可选「延后面板收起约 40ms」或
  「面板与键盘共用一个高度槽」；当前选的是重叠抵消。
- 图标许可：个人使用接受风险；商用需换图。
