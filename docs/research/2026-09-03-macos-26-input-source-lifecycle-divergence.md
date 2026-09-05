# macOS 26 输入菜单状态错位根因：偏离上游安装生命周期

日期：2026-09-03
范围：定位 RoType 0.2.15 已安装且洛克输入法已启用后，菜单栏仍显示豆包波形图标的问题。本轮只做诊断，不修改产品代码。

## 修正后的结论

`TextInputMenuAgent` 保留旧图标是**可复现的直接症状**，但不是应由产品主动重启代理来修复的底层原因。用户指出其他输入法日常切换不需要重启是正确的。

与官方 Squirrel 1.1.2 安装包逐项比较后，产品根因是 RoType 偏离了上游已经闭合的输入源安装生命周期：

1. 官方脚本执行 `register -> build -> enable -> select`；RoType 当前执行 `register -> enable -> open Squirrel -> kill TextInputMenuAgent -> kill ControlCenter`，删除了安装后的 `select`，却增加了上游不存在的系统代理重启。
2. 官方包声明 `postinstall-action="logout"`；RoType 包声明 `postinstall-action="none"`，却没有提供等价的登录会话初始化保证。
3. 官方只使用 TIS API；RoType 向导在 macOS 26 上跳过 `TISSelectInputSource`，并直接写入未公开的 `com.apple.HIToolbox/AppleEnabledInputSources`。偏好写入不会等价地产生 TIS、IMK 和菜单代理所需的完整运行时通知。
4. 官方 Hans mode 保留 `tsInputModeDefaultStateKey=true`，配合首次安装后的注销/登录完成物化；RoType 删除该键后又用私有偏好写回来补偿，形成第二套状态来源。

这些旁路叠加后，磁盘 Bundle、TIS 当前值、IMK controller、持久偏好和菜单栏图像可以各自处于不同代状态。`killall TextInputMenuAgent` 能让图标暂时恢复，只说明代理重新读取了正确状态，不代表正常输入法切换应依赖重启。

以下仍然成立：

- 洛克输入法已经安装；
- 洛克的 Bundle ID 和 mode ID 与豆包独立；
- `rotypeTemplate.pdf` 存在、可达且能正确渲染；
- Squirrel controller 能正常启动；
- Fn 没有被配置为切换输入源；
- 前台应用没有自动恢复文稿输入源。

## 官方原版对照

已下载但未安装官方 `Squirrel-1.1.2.pkg`，并用 `pkgutil --expand-full` 静态展开。实际包内容与 GitHub 源码一致。

官方 `PackageInfo`：

```xml
<pkg-info
  identifier="im.rime.inputmethod.Squirrel"
  install-location="/Library/Input Methods"
  postinstall-action="logout">
```

官方 postinstall 的核心顺序：

```bash
killall Squirrel
Squirrel --register-input-source
Squirrel --build
Squirrel --enable-input-source
Squirrel --select-input-source
```

官方没有：

- `killall TextInputMenuAgent`；
- `killall ControlCenter`；
- 写 `AppleEnabledInputSources`；
- 在 macOS 26 上刻意跳过 `TISSelectInputSource`；
- 打开系统设置作为安装流程的一部分。

官方所谓注销只针对首次安装后的 IMK 登录会话初始化。安装完成后在输入法之间日常切换不需要注销、重启或重启菜单代理。

## 本机重启时间线

```text
本次开机：2026-09-03 19:33:21 +0800
最新 RoType receipt 安装：2026-09-03 20:27:50 +0800
```

因此用户确实重启过，但最新 0.2.15 是在该次重启约 54 分钟后安装的。当前自定义 postinstall 随后重新执行了代理重启流程，所以此前重启不能阻止本次安装重新制造状态错位。

## 决定性 A/B 实验

实验前保持洛克为当前输入源，不改 Bundle、不改偏好、不重新安装。

### 重启前

`TISCopyCurrentKeyboardInputSource()`：

```text
current.id=im.roarkai.inputmethod.Luoke.Hans
current.bundle=im.roarkai.inputmethod.Luoke
current.enabled=true
current.selected=true
```

统一日志同时显示系统在向洛克请求菜单：

```text
Squirrel Activate Server
Squirrel Menu
```

TIS 为洛克解析出的图标 URL：

```text
/Library/Input Methods/洛克输入法.app/Contents/Resources/rotypeTemplate.pdf
reachable=true
```

但是后台屏幕截图 `/tmp/rotype-current-menubar.png` 中，菜单栏仍显示豆包波形图标。

### 唯一变量

只执行：

```bash
killall TextInputMenuAgent
```

没有再次调用 `TISSelectInputSource`，没有修改任何偏好。代理 PID 从 `73873` 变成 `94193`。

### 重启后

TIS 状态保持完全不变：

```text
current.id=im.roarkai.inputmethod.Luoke.Hans
current.bundle=im.roarkai.inputmethod.Luoke
current.enabled=true
current.selected=true
```

后台截图 `/tmp/rotype-menubar-after-agent-restart.png` 中，菜单栏图标立即变为 `R`。

因此，在本机复现条件下，`TextInputMenuAgent` 的生命周期是使错误图标消失的充分变量。图标文件和当前输入源均未改变。

## 截图时间线解释

用户截图 `/var/folders/_q/hf8rd6sd0qs_kl72lcf8mczw0000gn/T/otty-paste/image-1788438697839.png` 显示：

- 顶部勾选“豆包输入法”；
- 下方是豆包专属命令，例如语音输入、切换英文、英文标点和自定义短语。

该截图时 `TISCopyCurrentKeyboardInputSource()` 也返回豆包，统一日志由 `DoubaoIme` 响应 `menu()`。所以该截图本身不是“洛克已选中但显示豆包菜单”，而是当时真实当前输入源就是豆包。

之后程序化选择洛克，连续 10 秒稳定性探针始终返回洛克；在 Dia 与 Otty 间切换前台应用后也仍保持洛克。此时统一日志改为 `Squirrel Menu`，但状态栏图像仍是波形，直到单独重启 `TextInputMenuAgent` 才变为 `R`。

这说明现场曾有两个阶段：

1. 豆包确实是当前输入源；
2. 切到洛克后，controller/menu owner 已更新，但状态栏图像仍沿用豆包缓存。

把两个阶段混在一起，会错误归因为 Bundle 身份冲突或图标文件损坏。

## 已排除假设

### 1. 洛克没有启用

系统设置“文字输入”显示“豆包输入法和洛克输入法”。`com.apple.inputsources` 的 `AppleEnabledThirdPartyInputSources` 同时包含洛克 parent 和 mode：

```text
im.roarkai.inputmethod.Luoke
im.roarkai.inputmethod.Luoke.Hans
```

TIS 也报告洛克 mode `enabled=true`、`selectable=true`。

### 2. 图标文件错误

Apple SDK 的 `kTISPropertyIconImageURL` 是系统解析后的输入源图标 URL。本机对洛克 mode 的返回值精确指向 `rotypeTemplate.pdf`，且文件存在。

Apple 的 `TextInputSources.h` 说明：

- `kTISPropertyIconImageURL` 是输入源图像文件 URL；
- PDF 可以被支持；
- TIS 会尽可能通过 bundle image resource 解析资源。

本机 Quick Look 也能把该 PDF 正确渲染为 `R`。

### 3. Bundle 身份冲突

磁盘和 LaunchServices 中的有效输入法注册分别是：

| 输入法 | 路径 | Bundle ID | Mode ID | Team ID |
| --- | --- | --- | --- | --- |
| 洛克 | `/Library/Input Methods/洛克输入法.app` | `im.roarkai.inputmethod.Luoke` | `im.roarkai.inputmethod.Luoke.Hans` | `DF7J2VBQD8` |
| 豆包 | `/Library/Input Methods/DoubaoIme.app` | `com.bytedance.inputmethod.doubaoime` | `com.bytedance.inputmethod.doubaoime.pinyin` | `96L78H6LMH` |

没有共用 Bundle ID、mode ID、controller class 或签名身份。

### 4. 洛克 IMK controller 没有激活

选择洛克后的统一日志持续出现：

```text
Squirrel Activate Server
Squirrel Menu
```

选择豆包时则是：

```text
DoubaoIme Activate Server
DoubaoIme Menu
```

因此 controller owner 可以正确切换。错误只剩状态栏图像。

### 5. Fn 把输入源切回豆包

系统设置现场截图显示“按下地球键时：不执行任何操作”。当前 `AppleFnUsageType=0` 与该 UI 对应。因此本机 Fn 不负责切换输入源。

Apple 的 macOS 26 Keyboard Settings 文档列出 Fn/Globe 可配置为切换输入源、显示字符检视器、启动听写或不执行操作；现场 UI 明确选中最后一种。

### 6. 自动切换到文稿输入源

系统 Darwin 状态 `com.apple.inputmethod.perContextInputSourceEnabled` 为 `0`。此外，选择洛克后分别激活 Dia 和 Otty，真实 TIS 均持续返回洛克。因此前台应用切换不是本次回退机制。

### 7. 输入模式基础声明大体正确，但默认状态被改动

当前洛克和上游 Squirrel 都使用：

- `ComponentInputModeDict`；
- `tsInputModeMenuIconFileKey`；
- `tsInputModePaletteIconFileKey`；
- `smUnicodeScript`；
- `Squirrel.SquirrelInputController`。

所以 `smUnicodeScript`、controller class 和图标键不是异常配置。豆包使用 `smSimpChinese`，但 A/B 实验在不修改 script key 的情况下恢复了 `R`。

真正的 plist 差异是：官方 Squirrel 的 Hans mode 包含 `tsInputModeDefaultStateKey=true`，洛克当前删除了该键。这个差异不能单独解释切换后图标滞留，因为代理重启时 plist 未变而图标恢复；但它会改变首次注册/登录时 mode 如何进入系统默认启用状态。结合洛克取消 `postinstall-action="logout"`、跳过安装后 `select` 和直接写偏好，这项改动参与了安装状态分裂，必须作为完整生命周期一起恢复和验证。

## 安装顺序中的触发点

当前 `Installer/scripts/postinstall` 的相关顺序是：

1. 终止旧 Squirrel 和语音进程；
2. 注册洛克输入源；
3. 启动语音 LaunchAgent；
4. 启用洛克输入源；
5. 打开 Squirrel；
6. 重启 `TextInputMenuAgent`；
7. 重启 `ControlCenter`。

该流程没有在第 6 步前确认 `TISCopyCurrentKeyboardInputSource()` 已经是洛克。安装时如果豆包是当前输入源，代理会以豆包为初始状态启动。之后选择洛克虽然能让 Squirrel controller 接管并返回自己的 `menu()`，状态栏图像却不一定更新。

这与决定性实验完全一致：在洛克已 selected 后重新启动代理，`R` 立即出现。

## 最小复现与反馈循环

快速状态探针：

```bash
xcrun swift /tmp/rotype-tis-state-probe.swift
```

红态条件：

1. 探针输出 `current.id=im.roarkai.inputmethod.Luoke.Hans`；
2. 日志显示 `Squirrel Menu`；
3. 屏幕截图仍显示豆包波形图标。

验证变量：

```bash
old_pid=$(pgrep -x TextInputMenuAgent)
killall TextInputMenuAgent
# 等待新 PID 后后台截图；不要再次选择输入源。
```

绿态条件：

1. TIS 仍是洛克；
2. `TextInputMenuAgent` PID 已变化；
3. 菜单栏显示 `R`。

该循环已在本机完整执行一次并从红变绿。

## 修复方向，尚未实施

本轮只定位，不修改代码。后续不应继续增加代理刷新，而应收回自定义旁路，恢复上游的单一状态机：

1. 删除安装脚本中的 `killall TextInputMenuAgent` 和 `killall ControlCenter`；
2. 恢复 `enable` 后的 `select`，并验证 TIS selected 与 Squirrel controller 激活；
3. 删除应用直接写 `AppleEnabledInputSources` 的逻辑，只使用公开 TIS API；
4. 重新评估并优先恢复上游 `tsInputModeDefaultStateKey=true`，与安装生命周期一起验证，不能孤立修改；
5. 安装包要么像上游一样声明首次安装后注销，要么设计并验证明确的免注销流程，但不能通过强杀系统代理冒充会话初始化；
6. 品牌化只改稳定身份和资源，不改变 Squirrel 的注册、启用、选择语义。

目标验收不是“重启代理后图标正确”，而是：首次安装完成一次会话初始化后，洛克、豆包和系统输入源之间连续双向切换，图标、勾选项、controller owner 和实际输入每次同步变化，全程不重启任何代理。

## 主要资料

- Apple Xcode 26.5 SDK `TextInputSources.h`：`TISSelectInputSource`、`TISEnableInputSource`、`TISRegisterInputSource`、`kTISPropertyIconImageURL` 的契约，位于 `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/Carbon.framework/Frameworks/HIToolbox.framework/Headers/TextInputSources.h`
- Apple [Change Input Sources settings on Mac](https://support.apple.com/guide/mac-help/change-input-sources-settings-mchl84525d76/26/mac/26)
- Apple [Keyboard settings on Mac](https://support.apple.com/guide/mac-help/keyboard-settings-kbdm162/26/mac/26)
- Apple [`IMKInputController.menu()`](https://developer.apple.com/documentation/inputmethodkit/imkinputcontroller/menu%28%29)
- 上游 Squirrel [`resources/Info.plist`](https://github.com/rime/squirrel/blob/master/resources/Info.plist)
- 上游 Squirrel [`sources/InputSource.swift`](https://github.com/rime/squirrel/blob/master/sources/InputSource.swift)
