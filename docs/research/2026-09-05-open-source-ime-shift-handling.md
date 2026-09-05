# 开源输入法对照：Shift 与状态提示

## 查阅的一手源码

固定到 2026-09-05 查询到的提交，而不是凭印象套用：

1. **鼠须管** [`0cd71a6`](https://github.com/rime/squirrel/blob/0cd71a6130a5866b0ae6ba0494929ebdc8211194/sources/SquirrelInputController.swift#L54-L98)
   - 用修饰键差集区分按下/松开，先处理松开，再处理按下。
   - 对缺失或非修饰键的 keyCode，按变化的修饰键推断；源码明确提到远程桌面工具可能发送 keyCode 0。见 [键码推断](https://github.com/rime/squirrel/blob/0cd71a6130a5866b0ae6ba0494929ebdc8211194/sources/MacOSKeyCodes.swift#L68-L91)。不能据此断言本机物理键盘也存在相同缺失。
   - 激活时从 CGEventSource 的会话状态同步 Caps Lock，源码说明 NSEvent.modifierFlags 只反映进程自己的事件流。
   - [状态显示](https://github.com/rime/squirrel/blob/0cd71a6130a5866b0ae6ba0494929ebdc8211194/sources/SquirrelApplicationDelegate.swift#L338-L404)使用独立 NSStatusItem，按引擎实际状态显示方案短标签或“中 / Ａ”；离开鼠须管输入源时隐藏。不是把固定品牌图标当作中英文状态。

2. **Fcitx5 macOS** [`564a6b5`](https://github.com/fcitx-contrib/fcitx5-macos/blob/564a6b5c65cf52ca950118169892ed54fea28dee/src/controller.swift#L121-L195)
   - 显式向核心传递 isRelease。
   - 对 Shift+鼠标改变选区，发送 no-op 取消待触发的 Shift 切换；注释明确提醒 no-op 键码不能用 0，因为 macOS 的 0 是 A。
   - 对 activateServer/deactivateServer 不可靠的应用，在 handle 中重新绑定当前 controller。不是假定视觉焦点等于完整收到激活回调。
   - [status.swift](https://github.com/fcitx-contrib/fcitx5-macos/blob/564a6b5c65cf52ca950118169892ed54fea28dee/src/status.swift)对状态文字做短标签处理；仅凭这个函数不能推断所有光标提示行为。

3. **McBopomofo** [`f5ba010`](https://github.com/openvanilla/McBopomofo/blob/f5ba010ce8795d283ee336ca7d16380f200bd2ec/Source/InputMethodController.swift#L214-L278)
   - 按组合状态决定 flagsChanged 是否交给应用，并注册 keyUp。
   - 这段控制器不是“单按 Shift 持续切英文”的直接实现，不能照抄后声称已支持。
   - [NotifierController](https://github.com/openvanilla/McBopomofo/blob/f5ba010ce8795d283ee336ca7d16380f200bd2ec/Packages/NotifierUI/Sources/NotifierUI/NotifierController.swift)是独立临时通知窗口；与系统输入源光标浮层不是同一个模块。

## 对照后定位的 RoType 特有回归

RoType 在每次 flagsChanged 后调用 rimeUpdate，再通过 translationSnapshot 注入 F19。librime 的 ascii_composer 会把非修饰键视为真实的另一按键，清除待触发的 Shift 记录：

`Shift 按下 → 翻译查询 F19 → Shift 松开`

此前只测了连续 Shift 按下/松开，因此虽然键码 0 兼容和 inline_ascii 配置确有问题，修正它们仍不足以恢复本机切换。

对应本地源码：
- `Squirrel/sources/SquirrelInputController.swift`：rimeUpdate / translationSnapshot。
- `Squirrel/librime/src/rime/gear/ascii_composer.cc`：ProcessKeyEvent 的 other keys 分支清除修饰键记录。

新增真实 Rime 回归在已安装 build 35 上退出 191：
`FAIL: internal F19 snapshot cancelled Shift gesture: rotype`

## 最小修正

新增 `rotype_candidate_snapshot`，放在 ascii_composer 之前，仅转交 F19 给现有候选会话模块。读取快照不再进入键盘手势状态机；其他按键继续原处理链。

**不把整个候选会话处理器提前**：F20 是实际提交动作，仍应进入原处理链，使真实操作能正常取消单独 Shift 手势。快照/校验逻辑不复制，仍由 rotype_candidate_session 负责。

新旧对照后，全拼、小鹤的 Shift→F19→release、提交后英文保持、再次切中文、Shift+字母，以及原分页/整句/分段测试通过；常规测试及 32 个 Swift 测试也通过。

## 本机验证与边界

- 当前安装为 0.0.1/build 35；它只包含先前键码修正，打包的工厂方案尚无本次 F19 修正。不能把该包当作完整 Shift 修复包再次交付。
- 本机临时补丁：`~/Library/Rime/lua/rotype_candidate_snapshot.lua`，以及两份方案 custom 中的 `engine/processors/@before 0` 插入。修改前 custom 文件备份在 `/tmp/rotype-shift-before-f19/`。将来工厂方案含该前置处理器后，移除临时插入，避免重复。
- 已重新部署，编译配置确认快照处理器排在 ascii_composer 前。
- 独立真实 NSTextView 验证左 Shift：中文 nihao 有 marked text → Shift 后 hello 无 marked text → 再 Shift 后 nihao 恢复 marked text；三步均确认测试窗口为 keyWindow。这是已安装 IMK 路径，不只是核心测试。
- 随后右 Shift 自动测试遇到窗口焦点变化，结果作废；不声称右 Shift 已通过实际 UI 验收。停止继续发键，后续由用户手动验证或使用具备逐事件焦点保护的工具。
- 测试期间可能在其他前台窗口产生 hello/nihao 测试字符；不能自动全局撤销，避免误删用户自己的输入。
- 蓝色 R 不属于新增“中 / EN”原生绘制内容，但尚未捕获该瞬间的窗口归属，不能把“疑似系统光标浮层”写成已确认结论。不要通过全局偏好关掉所有输入法的系统提示。
