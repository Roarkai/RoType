# macOS 第三方输入法安装与注册：是否必须注销

更新时间：2026-09-02

## 结论

**不能把“首次安装后必须注销”当成 Apple 官方规定，也不能据此直接断定洛克输入法当前的问题只是缓存。**

Apple 随 Xcode SDK 提供的 `TextInputSources.h` 对 `TISRegisterInputSource` 的契约写得很明确：安装器可用它通知系统注册新输入源，系统执行必要的缓存重建，随后安装器应能**立即**用 `TISCreateInputSourceList` 取得新输入源。`TISEnableInputSource` 则使已注册输入源出现在可选择的 UI 中。Apple 的 [QA1810](https://developer.apple.com/library/archive/qa/qa1810/_index.html) 也给出了 `TISCreateInputSourceList` + `TISEnableInputSource` 的公开用法，并说明键盘输入法仍由“输入源”设置管理。

但实践中，**注销/重新登录是成熟开源输入法普遍保留的首次安装或异常恢复手段**：鼠须管的安装包直接声明 `RequireLogout`，AquaSKK 也如此，Fcitx5 macOS 明确要求首次安装后注销；macSKK 则先让用户直接添加，只有“安装后不显示或升级未刷新”时才建议注销。因此更准确的说法是：

- 正常、符合 API 契约的注册路径应尝试即时生效；
- 首次安装在部分系统/产品上可能仍需一次登录会话重建；
- 更新已注册的输入法通常只需结束并重启输入法进程；
- `TISRegisterInputSource == noErr` 但 `TISCreateInputSourceList(..., true)` 完全枚举不到新 ID，属于**注册没有形成可见结果**，不能只用“需要注销”解释，必须继续排查 bundle 元数据、代码签名/信任、安装位置和系统注册链。

## 证据表

| 来源 | 实际做法 | 能证明什么 | 不能证明什么 |
| --- | --- | --- | --- |
| Apple SDK `TextInputSources.h`（本机 Xcode SDK，第 1199–1254 行附近） | `TISRegisterInputSource` 的目标是让安装器注册 bundle、触发必要缓存重建，并“immediately”取得 `TISInputSourceRef`；同时明确支持 `/Library/Input Methods` 和 `~/Library/Input Methods` | Apple 公开 API 的设计目标是即时注册，两种目录都合法 | 不保证所有近代 macOS 实现都无 bug |
| Apple [QA1810](https://developer.apple.com/library/archive/qa/qa1810/_index.html) | 用 `TISCreateInputSourceList` 找输入源，再用 `TISEnableInputSource` 启用；键盘输入法仍在系统输入源面板管理 | 启用必须建立在“系统已经枚举出输入源”之上 | QA 发布于 Mavericks，未描述 macOS 14/15/26 的缓存回归 |
| Apple [IMKServer 初始化文档](https://developer.apple.com/documentation/inputmethodkit/imkserver/init%28name%3Abundleidentifier%3A%29) | 系统从 `Info.plist` 读取 `LSBackgroundOnly`、`InputMethodConnectionName`、`InputMethodServerControllerClass`、图标和字符集 | `Info.plist`/类名/连接名错误会破坏 IMK 注册或启动链 | 没说注销可修复无效元数据 |
| 鼠须管 1.1.2 [Release](https://github.com/rime/squirrel/releases/tag/1.1.2) | 明确要求安装后退出当前用户并重新登录；未出现时手动添加 | 鼠须管把注销作为产品级安装流程 | 不能证明所有输入法或每台 Mac 必须注销 |
| 鼠须管 [postinstall](https://github.com/rime/squirrel/blob/0cd71a6130a5866b0ae6ba0494929ebdc8211194/scripts/postinstall) 与 [InputSource.swift](https://github.com/rime/squirrel/blob/0cd71a6130a5866b0ae6ba0494929ebdc8211194/sources/InputSource.swift) | 先结束旧 Squirrel，调用 `TISRegisterInputSource`；再以登录用户身份 enable/select | 即使安装包最终要求注销，项目仍实施即时 register/enable/select，而不是只依赖注销 | `noErr` 本身不等于菜单一定可见 |
| 鼠须管 [Issue #281](https://github.com/rime/squirrel/issues/281) | 2019 年 Mojave 上覆盖更新后系统可能仍调用旧可执行文件，故恢复 `RequireLogout` | 注销的重要动机之一是**更新后的旧进程/旧引用**，并不只是首次发现 bundle | 这是项目维护者经验，不是 Apple API 规范 |
| macSKK [安装指南](https://github.com/mtgto/macSKK/blob/11af168496e3058e1f69152c18306636f21c0fed/docs/guide/install.md) | 安装后直接进入系统设置添加；仅在“安装后不显示或升级未反映”时建议注销/登录 | 成熟 InputMethodKit 产品存在“不把注销设为必经步骤”的反例 | 仍承认某些机器需要注销恢复 |
| macSKK [开发替换脚本](https://github.com/mtgto/macSKK/blob/11af168496e3058e1f69152c18306636f21c0fed/build_restart.sh) | 覆盖 `~/Library/Input Methods` 或 `/Library/Input Methods` 中的现有 app，然后只 `pkill macSKK` | 已注册输入法的后续开发更新可仅重启进程 | 不代表新 bundle ID 的首次注册也能只靠 `pkill` |
| Fcitx5 macOS [README](https://github.com/fcitx/fcitx5-macos/blob/9873ee9e0efaf35f818ebe17a4625dbb1cb6c1f0/README.md) | 首次安装后注销/登录；后续安装点击 Restart 即可 | 明确区分“首次发现”和“后续更新” | 不说明其要求来自 Apple 规范还是项目兼容性选择 |
| Fcitx5 [update.sh](https://github.com/fcitx/fcitx5-macos/blob/9873ee9e0efaf35f818ebe17a4625dbb1cb6c1f0/assets/update.sh) | 更新时避免删掉必须存在的文件，因为会进入 registered-but-not-listed 状态；最后 `killall Fcitx5` | 覆盖更新应保持 bundle 路径/注册身份稳定，避免先删后装造成系统状态裂开 | 不提供新输入源的即时注册方案 |
| AquaSKK [README](https://github.com/codefirst/aquaskk/blob/0e7a88f4713299de2c42c71a088bfe458fc0e3cd/README.md) 与 [installer distribution](https://github.com/codefirst/aquaskk/blob/0e7a88f4713299de2c42c71a088bfe458fc0e3cd/platform/mac/pkg/distribution.xml) | 文档说“可能需要”注销，pkg 配置 `RequireLogout` | 这是另一个长期维护输入法采用注销兜底的例子 | 项目较旧，不能独立证明 macOS 26 行为 |

## macOS 14、15、26 应如何区分

目前没有找到 Apple 官方文档宣布：macOS 14、15 或 26 改成了“第三方 InputMethodKit 输入法首次安装必须注销”。公开 API 契约仍是即时注册。

- **macOS 14+**：macSKK 明确记录了 App Sandbox/容器访问对 Team ID、Provisioning Profile、ad-hoc 签名差异更敏感；这影响开发版与发行版身份和数据访问，但不等于必须注销。
- **macOS 15**：未找到与“首次注册必须注销”直接相关的 Apple 变更说明。
- **macOS 26**：鼠须管已有 `TISSelectInputSource` 程序化切换后的 activate/deactivate 回归报告（[#1140](https://github.com/rime/squirrel/issues/1140)、[#1162](https://github.com/rime/squirrel/issues/1162)），但它们发生在**已经注册的输入源切换阶段**，不能当作新输入源注册失败的证据。

所以，“这是 macOS 26 已知注册问题”目前证据不足；之前这样表述不严谨。

## 安装位置、签名与公证

### 安装位置

Apple SDK 明确允许两处：

- `/Library/Input Methods`：全体用户可用，安装通常需要管理员权限，系统级 pkg 适合放这里；
- `~/Library/Input Methods`：仅当前用户可用，适合本机开发和免管理员安装。

二者都可传给 `TISRegisterInputSource`。路径本身不是“必须注销”的充分原因。

### 签名与公证

面向其他用户分发时，应把签名、公证当作发布硬要求。Apple 的[公证文档](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)要求直接分发的软件使用 Developer ID、Hardened Runtime 和安全时间戳，并明确不要使用 Apple Development、ad-hoc 或带 `get-task-allow=true` 的构建；[Developer ID 证书说明](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)区分了 Application 和 Installer 两种证书。

这意味着当前仅用 **Apple Development** 签名、`spctl` 显示 rejected 的洛克安装包还不是可对外发布的合格包。它也可能干扰系统信任链，但现有 Apple 文档没有写明“未公证会导致 `TISRegisterInputSource` 返回 `noErr` 却不枚举”，所以不能把当前注册失败单因归结为未公证。

## 哪些“刷新方案”可靠

按可靠性排序：

1. **官方路径：** bundle 完整落盘后，调用 `TISRegisterInputSource(bundleURL)`，检查返回码；再用具体 Bundle ID/InputSource ID 调 `TISCreateInputSourceList(..., true)`，确认能枚举；最后对正确 mode 调 `TISEnableInputSource`，必要时 `TISSelectInputSource`。
2. **手动添加：** 如果已能在系统设置的“添加输入源”中看到，交给用户添加是正常产品流程；macSKK 就采用此方式。
3. **已注册后的更新：** 保持相同路径和 bundle identity，先优雅退出/结束旧输入法进程，原子覆盖，再重启输入法。macSKK、Fcitx5 都证明这是常规开发/升级路径。
4. **登录会话重建：** 首次安装仍无法发现，或系统继续引用旧二进制时，注销/登录是成熟项目采用的强兜底，但应在前面诊断完成后再要求用户操作。

以下方法只能作为诊断辅助，不能替代注册成功证明：

- `killall`/`pkill` 输入法：只能重启已注册服务，不能保证发现新 bundle ID；
- 重启 `TextInputMenuAgent` 或系统设置：只刷新 UI，前提是 TIS 已有可枚举输入源；
- LaunchServices `lsregister`：是非公开/实现细节工具，LaunchServices 能看到 app 不等于 TIS 已生成输入源；
- 直接修改 `com.apple.HIToolbox` preferences：可能制造“设置里有条目但菜单不可用”的幽灵状态，不应作为安装实现；
- `killall cfprefsd`、删除系统缓存：没有 Apple 支持文档，风险大，不应进入产品安装流程。

## 对 RoType 的具体建议

### 现在不要先要求用户注销

当前已经观察到：

- 旧的品牌 ID `com.roarkai.rotype.inputmethod` 在 `TISCreateInputSourceList(nil, true)` 中完全不存在；后续实机二分确认，改为 InputMethodKit 兼容且独立的 `im.roarkai.inputmethod.Luoke` 后可立即枚举。
- `TISRegisterInputSource` 报 `noErr` 后仍无法枚举；
- 系统“添加输入源”界面也没有洛克输入法；
- 当前包仅 Apple Development 签名，`spctl` 不接受。

这组证据说明“输入法已正确注册、只差 UI 缓存”尚未成立。建议按以下门槛继续：

1. 安装后立即以**具体 bundle ID 和 mode ID**查询 TIS；只有查到 source 才执行 enable/select。
2. 把 installer/设置界面的“已验证”定义为：bundle 存在 + 签名完整 + TIS 可枚举 + source enabled + 当前输入菜单实际存在；任一失败都不能显示绿色完成。
3. 校验安装后真实 `Info.plist` 与运行时类：`CFBundleIdentifier`、mode ID、`InputMethodServerControllerClass`、`InputMethodConnectionName`、字符集/语言声明必须一致；用 `NSClassFromString` 或最小 IMK 启动探针验证 controller class 可解析。
4. 开发阶段可比较 `~/Library/Input Methods` 与 `/Library/Input Methods`，但不要同时保留相同 bundle ID 的多个副本；每轮先确认 LaunchServices 与 TIS 只指向一个真实路径。
5. 发布阶段取得 **Developer ID Application** 和 **Developer ID Installer**，移除 `get-task-allow`，开启 Hardened Runtime，公证并 staple，再在一台没有开发缓存的 Mac/干净用户上做首次安装验收。
6. 上述检查全部通过而首次登录会话仍不枚举时，再把“一次注销/登录”作为安装完成步骤；登录后必须重新运行菜单级验收脚本，不能只看设置页。

### 验收顺序

```text
pkg 安装成功
  -> 磁盘上只有一个目标 bundle
  -> codesign --verify 通过，发布包 spctl accepted
  -> TISRegisterInputSource 返回 noErr
  -> TISCreateInputSourceList(..., true) 能查到目标 mode
  -> TISEnableInputSource 后 enabled=true
  -> macOS 顶部输入菜单出现“洛克输入法”
  -> 可切换、可输入、候选正常
```

前五步未通过时，注销不是根因修复；全部通过但菜单仍旧时，才是缓存/UI 刷新问题。
