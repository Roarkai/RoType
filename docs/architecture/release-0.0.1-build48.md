# Build 48：直接填入、原生字母徽标、权限状态

## 交付

Developer ID 签名、Apple 公证、stapling、Gatekeeper 均通过。公证 ID：`2f86f144-172b-42e3-8be2-9f2e191dbb41`。

包已复制到 `~/Downloads/洛克输入法-0.0.1-build48-macOS-arm64.pkg` 并打开；最近检查仍安装 Build 47。尚未宣称本版完成真实 Fn、终端插入或菜单像素验收。

## 一会儿填入、一会儿待复制

- 确认旧 `VoiceInsertionPolicy` 对 Terminal、iTerm2、Ghostty 等整类拒绝，即使普通单行文字、原生输入票据有效也拒绝。修改期望为允许普通文字，运行 `swift test --filter voiceDoesNotExecuteTerminalInputOrInsertControlCharacters`，旧实现确定性出现三项失败。
- 移除应用黑名单，仍使用同一个 IMK `insertText` 路径。识别段落分隔符先转为空格；原生提交端仍拒绝原始换行、Tab、Escape 等控制字符。不会模拟粘贴、回车或发送。
- 保留签名角色、原应用/激活/选择范围、单次票据、有效期、Secure Input 和取消检查；不是向当前任意输入框强行写入。
- 缺少原生连接、目标变化和提交拒绝分别显示原因。HUD 从「文字待复制」改成「未能填入」，展开可见原因和原文；复制只是失败时的备用路径。
- 已插入的最近结果明确标记「已自动填入，此处仅保留备份，无需再复制」，按钮改为「复制备份」。
- 该路径的控制器/原生服务使用同一控制字符策略；新测试覆盖段落转换、终端文本投递、一次性提交及目标变化。

## 图标：不能再把 PDF 尺寸当成系统渲染

- 用户实际菜单截图：ABC 44×32 px，旧 R 26×26 px。可复跑：
  `swift Tests/MenuIcon/CompareScreenshot.swift <原截图> 55 63 59 44 55 160 59 41`。
- 本机只重启 `TextInputMenuAgent`，没有重启 SystemUIServer、移除输入源、修改 TIS 选择或重置系统偏好。刷新后 R 高度改善但仍窄，排除「只刷新缓存即可全部解决」。
- 只读查询实际 ABC 元数据：`TISPropertyInputSourceIconLabels = { Primary = A; }`，而已安装 Luoke 两个源均没有 labels。
- Apple 随系统 TamilIM 的 Info.plist 也使用 `TISIconLabels / Primary`。本版在 `.Hans` 模式中设 `TISIconLabels = { Primary = R; }`，交给同一系统字母徽标渲染器；宽版 PDF 只留作旧系统回退。
- 不调用私有渲染 API，不往产品加入诊断期的 `dlsym` 读取代码。解包已确认 Primary=R；最终实际菜单宽高仍须安装后用真实截图确认。
- PDF 测试输出已明确标为回退文件检查，不能作为系统菜单视觉证据。

## 权限区

- 麦克风使用 `AVCaptureDevice.authorizationStatus`，辅助功能使用只读 `AXIsProcessTrusted`。
- 分别显示「已授权」绿色圆形对勾、「待授权」「未授权」「系统限制」「无法读取」，附真实 TCC 应用名称和对应操作。
- 进入页面、回到窗口以及页面活跃时每两秒刷新；读取不触发授权弹窗。仅用户点击「去授权」时申请。
- 键盘设置是快捷键配置，不伪装成第三个已授予权限。
- 已检查授权/未授权两种原生离屏夹具；夹具不是用户真实权限证据。

## 验证

- `scripts/test.sh`：严格 SwiftLint、键盘/候选/安装源断言、70 项 Swift Testing 通过。
- Release 主输入法与 helper 编译、签名 XPC 隔离、麦克风元数据检查、GPU self-test 通过。
- 解包主程序 Build 48、原生徽标 Primary=R、深层严格签名检查通过。
- 不做自动桌面键入。真实终端场景仍由用户按 Fn 验收，不能把模拟 transport 测试说成实际麦克风输入已验收。

本机证据：`/tmp/rotype-release-0.0.1-b48/`；UI 夹具：`/tmp/rotype-b48-preview/`。
