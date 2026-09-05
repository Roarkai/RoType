# macOS 26 输入菜单身份错位诊断

日期：2026-09-03
范围：只定位截图中“顶部勾选豆包，分隔线下又出现灰色豆包标题和豆包命令”的来源，以及 RoType 0.2.x 反复安装后的输入源身份、注册与缓存状态；不执行修复。

## 结论

**截图不能解释成“洛克输入法挂在豆包输入法下面”。截图显示的是：当时真实的顶部输入菜单仍由豆包输入法拥有。**

菜单中两处“豆包输入法”来自不同层：

1. 顶部带勾的“豆包输入法”是系统列出的当前输入源。它的 UI 名称对应 TIS 的 `kTISPropertyLocalizedName`；Apple 头文件说明该值由输入源 bundle 的本地化资源按当前语言匹配。豆包安装包中，mode ID `com.bytedance.inputmethod.doubaoime.pinyin` 在 `InfoPlist.strings` 中也正好映射为“豆包输入法”。
2. 分隔线下灰色的“豆包输入法”是 `TextInputMenuAgent` 为**当前活动输入法的自定义命令区**自动加的 owner 标题。Apple 对 [`IMKInputController.menu()`](https://developer.apple.com/documentation/inputmethodkit/imkinputcontroller/menu%28%29) 的定义是“返回该输入法特有的命令菜单”，且每次绘制菜单都会调用；系统把返回项挂在这个灰色标题下面。它表示“下面这些命令由哪个输入法提供”，不是 RoType 隶属于豆包。

第二点有比截图更直接的二进制证据。当前豆包 `DoubaoImeInputController.menu` 调用其 `Menu.swift` builder，反汇编可见它创建四个操作项（selectors 包括 `createASRPanelIfNeed:`、`switchToEnglish:`、`toggleFullWidthInput:`、`toggleEnglishPunctuation:`），然后添加 separator 和“豆包输入法设置”；**builder 内没有创建灰色的“豆包输入法”标题**。所以灰色标题来自系统的菜单包装层，不是豆包返回的普通 `NSMenuItem`。

RoType 自己的 `SquirrelInputController.menu()` 目前又额外手写了一个 action 为 `nil`、`isEnabled = false` 的“洛克输入法”项，然后追加洛克设置和项目主页。这是 RoType 返回菜单里的自定义标题，与系统自动 owner 标题不是同一个来源，未来激活成功后反而可能显示两个标题。无论是否保留这个自定义项，只要当时系统在向 RoType controller 取菜单，后面的命令就应是 RoType 命令；截图却完整显示豆包自己的命令。

因此截图的强结论是：

- 豆包 controller 在当时仍是菜单命令的提供者；
- RoType 没有完成“系统菜单可见、原生选中、IMK controller 激活”这条链；
- System Settings 中能看到“洛克输入法”，以及 TIS API 返回 RoType 已选中，都不足以推翻真实菜单证据。

## 四个容易混淆的名字

| UI / 对象 | 来源 | 当前 RoType 值 | 是否能解释灰色“豆包输入法” |
| --- | --- | --- | --- |
| 顶部可勾选输入源名称 | `kTISPropertyLocalizedName`；通常由 `InfoPlist.strings` 中以 input source/mode ID 为 key 的本地化值产生 | `im.roarkai.inputmethod.Luoke.Hans` -> “洛克输入法” | 解释顶部带勾项 |
| bundle 对用户显示名 | `CFBundleDisplayName` / `CFBundleName` | “洛克输入法” | 是系统生成 owner 标题的可能回退来源之一，但截图无法单独区分 |
| 输入法专属命令区 | 活动 `IMKInputController.menu()` 返回的 `NSMenu`，再由 `TextInputMenuAgent` 加 owner 标题 | RoType 返回洛克命令；当前还额外返回一个禁用的“洛克输入法”自定义项 | **决定灰色标题下面出现谁的命令**；豆包二进制没有返回灰色标题本身 |
| 当前服务 owner | IMK 为当前文本输入 session 创建并激活的 controller | `Squirrel.SquirrelInputController`，server 用 `RoTypeInputMethod_Connection` + `im.roarkai.inputmethod.Luoke` 初始化 | 决定哪个输入法的专属命令区被展示 |

Apple SDK 还明确区分了身份：`kTISPropertyInputSourceID` 是唯一 reverse-DNS 输入源 ID；input mode 通常是父输入法 bundle/input source ID 加唯一后缀。`ComponentInputModeDict` 定义 mode，`tsInputModeMenuIconFileKey` 定义 mode 在菜单里的图标。图标、名字和 controller owner 是三个独立字段，不能互相代替。

**灰色 owner 标题最终取父输入法的 localized source name，还是直接取 `CFBundleDisplayName`，公开 `IMKInputController.menu()` 文档没有说明。** 当前豆包的 parent localized name、mode localized name 和 `CFBundleDisplayName` 都是“豆包输入法”，RoType 的三者也都相同，因此现有安装包无法做字段级二分。已能确定的是：标题由系统包装层生成、随非空 IMK 专属菜单出现，并标识该菜单的活动 owner；不是 RoType 的名称字段，也不是从属关系。

## 本机现场证据

以下均为 2026-09-03 在当前机器上的检查。磁盘、身份和进程检查是只读的；split-brain 快照是在执行一次可逆的 `TISSelectInputSource` 程序化切换后采样，用于复现“API 已切换、菜单 owner 未切换”的故障。

### 1. RoType 与豆包的磁盘身份完全独立

| 字段 | RoType | 豆包 |
| --- | --- | --- |
| 路径 | `/Library/Input Methods/洛克输入法.app` | `/Library/Input Methods/DoubaoIme.app` |
| Bundle ID | `im.roarkai.inputmethod.Luoke` | `com.bytedance.inputmethod.doubaoime` |
| Mode ID | `im.roarkai.inputmethod.Luoke.Hans` | `com.bytedance.inputmethod.doubaoime.pinyin` |
| Controller class | `Squirrel.SquirrelInputController` | `DoubaoImeInputController` |
| 代码签名 Team ID | `DF7J2VBQD8` | `96L78H6LMH` |

LaunchServices 也只记录了各自路径和各自签名，没有发现 RoType 被登记成豆包 bundle。当前 TIS 全量枚举只找到 RoType 的两个目标 ID，没有残留的 `com.roarkai.rotype.inputmethod` 或 `im.rime.inputmethod.Squirrel` 输入源。

**所以“RoType 与豆包用了相同 bundle ID / InputSourceID / controller class”不是当前证据支持的根因。** 可执行文件仍名为 `Squirrel`，Swift module 也仍名为 `Squirrel`，但 IMK server 在 `Main.swift` 中用当前 bundle 的独立 connection name 和 bundle identifier 初始化；没有证据表明进程文件名会把它归给豆包。

### 2. 当前登录会话处于 split-brain 状态

同一时刻观察到：

- `TISCopyCurrentKeyboardInputSource()` 返回 `im.roarkai.inputmethod.Luoke.Hans`；该 source 的 `IsEnabled=true`、`IsSelected=true`、`IsSelectCapable=true`。
- `com.apple.HIToolbox` 的 `AppleSelectedInputSources` 也记录 RoType。
- macOS 26 的 `~/Library/Preferences/com.apple.inputsources.plist` 中，未公开的 `AppleEnabledThirdPartyInputSources` 同时包含豆包父/子项和 RoType 父/子项。
- 但对 `TextInputMenuAgent` 的无障碍树只看到一个顶部输入源“豆包输入法”，看不到可选择的“洛克输入法”；截图也相同。
- 当时 RoType 的 `Squirrel` 进程和豆包的 `DoubaoIme` 进程都在运行。

这已经排除了“设置页文字看错”这种简单解释。**TIS 当前值、偏好持久化、菜单物化状态和活动 IMK controller 彼此不同步。** RoType 设置应用现在只比较 `TISCopyCurrentKeyboardInputSource()` 的 ID，因此仍可能把这种 split-brain 误判成“系统确认选中”。

### 3. 安装历史确实多次改变过身份

本机备份显示至少经历了三代输入法身份：

- 上游 `im.rime.inputmethod.Squirrel` / `Squirrel_Connection`；
- 早期 RoType `com.roarkai.rotype.inputmethod` / `RoTypeInputMethod_Connection`；
- 当前 `im.roarkai.inputmethod.Luoke` / `RoTypeInputMethod_Connection`。

同时曾出现 PackageKit 生成的 `.localized`、`-1.localized` 重定位副本。当前安装脚本已备份并清理这些路径，当前 LaunchServices/TIS 也只剩目标 RoType ID；所以旧身份是**登录会话状态失配的风险放大器**，但不是“豆包名称被写进 RoType bundle”的证据。

## 最可能的故障链

### A. 已证实：验收逻辑把 TIS readback 当成真实激活

`InputSourceManager.refresh()` 只检查 `TISCopyCurrentKeyboardInputSource()` 是否等于 `im.roarkai.inputmethod.Luoke.Hans`，相等就置 `selectionVerified = true`。现场恰好出现“该 API 返回 RoType，但真实菜单仍是豆包”的反例。

这能直接解释为什么多个版本的设置向导都可以显示绿色，而用户看到的问题不变：版本修了 bundle 元数据、路径和读回，但**验收信号仍停在 TIS 层，没有证明菜单 owner 和真实输入链已切换**。

### B. 高概率：macOS 26 的程序化切入没有激活 IMK controller

上游 Squirrel [Issue #1162](https://github.com/rime/squirrel/issues/1162) 在 macOS 26.5.2 记录了完全同层的异常：外部进程调用 `TISSelectInputSource` 切入后，TIS 已返回 Squirrel 为当前源，但 `IMKInputController` 没有激活，键盘仍走旧通道，输入菜单也没有正常的 Squirrel 专属项；用系统菜单原生切换则正常。相反方向的生命周期缺失见 [Issue #1140](https://github.com/rime/squirrel/issues/1140)，其兜底修复见 [PR #1142](https://github.com/rime/squirrel/pull/1142)。azooKey 也有独立的 [`TISSelectInputSource` 外部切换与真实输入不一致报告](https://github.com/azooKey/azooKey-Desktop/issues/340)。

截图比 #1162 多保留了一整套豆包命令，表明旧的豆包 controller/menu 仍在服务或 UI 仍持有它的菜单快照。机制细节尚未用 RoType 的 `activateServer` 日志直接抓到，所以此项是高概率，不写成 100% 已证实。

### C. 可能同时存在：注册/启用结果尚未物化到当前菜单 session

Apple SDK 的 [`TextInputSources.h`](https://github.com/phracker/MacOSX-SDKs/blob/master/MacOSX10.15.sdk/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/Headers/TextInputSources.h) 对 `TISRegisterInputSource` 的契约是：注册指定 bundle，进行必要的 cache rebuild，并允许随后立即枚举。Apple [QA1810](https://developer.apple.com/library/archive/qa/qa1810/_index.html) 也展示了枚举后 `TISEnableInputSource` 的公开路径。本机 Xcode 26.5 SDK 仍保留同一契约；链接为旧版 Apple SDK 的公开镜像，便于浏览器直接查看。

但成熟输入法仍将退出登录作为现实兜底。Squirrel [1.1.2 release](https://github.com/rime/squirrel/releases/tag/1.1.2) 明确要求安装后注销再登录，未出现时再手动添加；其 [PR #1161](https://github.com/rime/squirrel/pull/1161) 还修过 `TISRegisterInputSource` 指向不存在目录、但因为 macOS 自动发现而长期被掩盖的问题。

一份 2026 年第三方 IMK 实机研究还报告：`TISGetInputSourceProperty(...IsEnabled)` 可能受 `tsInputModeDefaultStateKey` 影响而显示 `true`，即使 UI 会话没有真正加入；`TISEnableInputSource` 对第三方 mode 也可能返回 `noErr` 却不物化。见 Nagi [Issue #33](https://github.com/nvalleo/nagi/issues/33) 和后续 [Issue #34](https://github.com/nvalleo/nagi/issues/34)。这是社区实测，不是 Apple 保证，但它与本机的 split-brain 现象一致。

RoType 当前 `SquirrelInstaller.register()` 和 `enable()` 都先调用 `enabledModes()`；只要 `IsEnabled` 为真就提前返回。这条 guard 因而可能把“可枚举/默认启用”误当成“已进入真实 UI 列表”。不过当前 `com.apple.inputsources.plist` 已含 RoType，不能只靠这一点解释全部现象。

## 关于 clone / rename 的身份规则

将 Squirrel 克隆成独立 IMK 输入法时，需要作为一个整体改变并保持稳定：

- `CFBundleIdentifier`；
- 顶层 `TISInputSourceID`；
- `ComponentInputModeDict` 的 key、内部 `TISInputSourceID` 和 visible ordered array；
- `InputMethodConnectionName`；
- `InfoPlist.strings` 中以父 ID / mode ID 为 key 的显示名；
- 设置应用、安装器和测试中查找的 mode ID。

Apple SDK 说明 input source ID 必须唯一，mode ID 通常继承父 ID。社区的 Yahoo KeyKey [PR #29](https://github.com/teddychan/yahoo-keykey-2/pull/29) 还给出一个实机反例：改品牌时 bundle ID 不再含点分隔的 `inputmethod` 后，`TISRegisterInputSource` 返回成功却不注册；恢复独立且兼容的 ID 后才出现。RoType 当前 `im.roarkai.inputmethod.Luoke` 已满足这一经验要求。

开发版和发行版不应在不同路径复用相同 bundle/mode ID。Yahoo KeyKey 的同一 PR 专门给 debug build 使用独立 ID，因为同 ID 的两份 bundle 会在 LaunchServices/TIS 中互相遮蔽。RoType 当前磁盘扫描没有这种并存，但大量历史重定位副本说明安装流程曾经落入过这个风险区。

图标键不会决定 owner：Apple SDK 的 `tsInputMethodIconFileKey` 是父输入法图标，`tsInputModeMenuIconFileKey` 是具体 mode 菜单图标，缺少 mode 图标时才可能回退。RoType 当前 mode 指向 `rotypeTemplate.pdf`；即使图标缓存错误，也不能把豆包的自定义语音/标点命令变成 RoType 命令。

## 判别探针

按信息增益排序，先做前四项即可定位到具体层。所有判定必须在同一个前台文本输入框、同一时刻采样。

### 1. 四信号同步快照（只读）

同时记录：

1. `TISCopyCurrentKeyboardInputSource()` 的 ID、localized name、selected/enabled/selectable；
2. `defaults read com.apple.HIToolbox AppleSelectedInputSources`；
3. `defaults read com.apple.inputsources AppleEnabledThirdPartyInputSources`；
4. `TextInputMenuAgent` 的全部顶部可选项、勾选项、分隔线下专属命令；
5. `ps` 中 RoType 与豆包进程 PID。

判定：TIS=RoType 而菜单勾选/专属命令=豆包，即可定义为 TIS/IMK split-brain，不能再显示“已验证”。

### 2. 系统原生点击对照

前提是菜单中确实出现可点击的“洛克输入法”。分别做两组：

- 从顶部系统菜单手动点“洛克输入法”；
- 从外部程序调用 `TISSelectInputSource`。

立即比较：灰色标题、专属命令、`activateServer` 日志和实际候选输入。若原生点击稳定变成“洛克输入法”命令并能打候选，而程序化路径仍显示豆包或空菜单，#1162 同类回归基本坐实。

若顶部菜单根本没有“洛克输入法”，先不要做 selection 结论；那是“启用状态尚未物化到菜单”层的问题。

### 3. controller 生命周期插桩

给 RoType 的以下位置加统一时间戳、PID、client bundle ID、当前 TIS ID（后续修复阶段再做，不在本次改代码）：

- `SquirrelInputController.init`；
- `activateServer`；
- `deactivateServer`；
- `menu()`；
- `handle(_:, client:)` 第一笔键事件。

菜单打开后应看到 `menu()`；切入后应看到 `activateServer`；敲字后应看到 `handle`。TIS=RoType 但三者未出现，故障就在 macOS 的 TIS -> IMK 激活边界，不在 Rime schema。

### 4. 菜单来源 canary

测试包把四个来源故意设成不同值：

- `CFBundleDisplayName = RoType Bundle Canary`；
- parent source ID 本地化 = `RoType Parent Canary`；
- mode ID 本地化 = `RoType Mode Canary`；
- `menu()` 第一个真实命令 = `RoType Menu Canary`，并删除当前手写的禁用标题。

原生选中后观察灰色 owner 标题具体命中哪个 canary，即可严格区分它取 bundle display name、parent localized name 还是 mode localized name；真实命令 canary 则证明 TextInputMenuAgent 当前拿到的是哪一版、哪一个 controller 的 `menu()`。

### 5. 登录会话重建对照

在确认磁盘只有一个 RoType identity、`com.apple.inputsources` 已含父/子项后，做一次注销/登录，再重复探针 1。若菜单恢复而 bundle、TIS 枚举结果都未变，说明修复对象是登录会话的菜单/IMK 注册物化，不应继续修改产品名称。

### 6. 干净用户对照

同一个已签名包在新 macOS 用户中首次安装，只通过 System Settings 手动添加和系统菜单手动选择。若干净用户正常、现用户异常，历史三代 ID 和重定位副本造成的会话残留权重上升；若同样异常，优先查当前 bundle 元数据、macOS 26 激活链和安装器 guard。

## 当前置信度

| 判断 | 置信度 | 理由 |
| --- | --- | --- |
| 灰色“豆包输入法”是系统为活动 IMK 专属菜单加的 owner 标题，不是豆包 `menu()` 返回项 | 很高（约 99%） | Apple `menu()` 契约；豆包 `Menu.swift` builder 的反汇编只有四个操作项、separator、设置项 |
| 灰色标题具体取 parent localized name、mode localized name 还是 `CFBundleDisplayName` | 未决 | 两个现有输入法的这些字段都同名；需用差异化 canary 二分 |
| 截图时豆包 controller/menu 仍拥有真实菜单 | 很高（约 95%） | 顶部勾选、灰色标题和全部豆包专属命令一致；没有 RoType 专属命令 |
| 当前主要问题是 TIS/偏好/UI/IMK controller 的 split-brain，而不是豆包与 RoType 共用 ID | 很高（约 95%） | 现场同步快照不一致；磁盘、LaunchServices、签名、TIS ID 均独立 |
| macOS 26 `TISSelectInputSource` 激活竞态是直接触发器 | 高（约 80%） | Squirrel 与 azooKey 有同层复现；RoType 尚缺自身 activate/menu 时间线插桩 |
| 历史 rename / PackageKit relocation 是唯一根因 | 低（约 30%） | 它会放大缓存风险，但当前枚举和 LaunchServices 已只剩目标 ID；无法单独解释程序化激活回归 |

## 源码与官方资料

- Apple [`IMKInputController.menu()`](https://developer.apple.com/documentation/inputmethodkit/imkinputcontroller/menu%28%29)
- Apple [`TextInputSources.h` 的在线 SDK 镜像](https://github.com/phracker/MacOSX-SDKs/blob/master/MacOSX10.15.sdk/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/Headers/TextInputSources.h)（本机 Xcode 26.5 SDK 仍保留相同的身份、注册和启用契约）
- Apple [QA1810: Third-Party Input Method Management Changes](https://developer.apple.com/library/archive/qa/qa1810/_index.html)
- Apple [Core Foundation bundle name keys](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html)
- 上游 Squirrel [`SquirrelInputController.menu()`](https://github.com/rime/squirrel/blob/master/sources/SquirrelInputController.swift#L242)
- 上游 Squirrel [`InputSource.swift`](https://github.com/rime/squirrel/blob/master/sources/InputSource.swift)
- 上游 Squirrel [macOS 26 程序化切入回归 #1162](https://github.com/rime/squirrel/issues/1162)
- 上游 Squirrel [注册路径修复 #1161](https://github.com/rime/squirrel/pull/1161)
