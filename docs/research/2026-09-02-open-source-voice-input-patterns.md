# 开源语音输入法方案调研（RoType）

> 调研快照：2026-09-02。仅使用项目自己的 GitHub 仓库、README、源码和许可证；未安装或运行这些应用。链接尽量固定到本次核验的提交，避免后续源码漂移。

## 结论先行

RoType 不需要移植另一个完整语音应用，也不应该引入 Tauri、Python 或新的菜单栏常驻进程。最合适的融合方案是：

1. 以 **SaidDone/Pindrop** 的 provider seam 为骨架：`SpeechTranscribing` 同时承载豆包和本地 Whisper，AppDelegate 只编排状态，不写供应商协议。
2. 豆包第一版保持 **整段录音 → HTTP 极速识别**。SaidDone 已验证 Swift 下的请求形状、业务状态码和 mock 测试路径；实时流式留接口，不在第一版扩大复杂度。
3. 以 **Yap/Handy** 的录音与投递可靠性为标准：先捕获目标 App、避免首词丢失、显式处理取消/设备变化/忙碌重入，粘贴后仅在仍拥有剪贴板时恢复。
4. 以 **VoiceScribe/Whispering** 的显式生命周期驱动状态浮窗：`idle → recording → transcribing → inserting → delivered / clipboardFallback / failed`。
5. 首次向导采用 **权限 → 语音服务 → 豆包凭据测试 → 热键 → 试说一句 → 完成**；日常设置按“语音、快捷键、双语候选、隐私与诊断”分组。
6. 豆包 Access Token 必须进 macOS Keychain。云端必须显式告知“音频会上传”，不能暗中降级或把云端描述为本地。

## 项目对比

| 项目 | 技术与许可 | 热键/录音 | ASR 模式 | 插入与可靠性 | UI/配置 | 对 RoType 的价值 |
|---|---|---|---|---|---|---|
| [SaidDone](https://github.com/Chaoqi31/saiddone/tree/22edb02db96474b567556ab91fcb2ba601d3b39d) | Swift/SwiftUI，macOS 14+，MIT | 全局热键；整段采集后进入 pipeline | WhisperKit、本地 LLM、云 ASR；含专用豆包极速实现 | 剪贴板 + Cmd-V；恢复旧剪贴板；无权限时保留文本 | 七步 onboarding、provider 设置、连接测试；密钥 Keychain | **豆包接入的第一参考**：技术栈、最低系统版本和 RoType 最接近 |
| [Pindrop](https://github.com/watzon/pindrop/tree/6668d098ac1e1594600d5fdd6c376a1f06aee9a7) | 原生 Swift/SwiftUI，MIT | Carbon 全局热键，支持 toggle/PTT down/up；录音统一 16 kHz PCM | 本地/云端统一引擎协议 | 原生投递链路 | 欢迎、模型、权限、热键、完成；非敏感配置与 Keychain 分离 | provider 状态接口、录音 backend 可测试性、首次引导顺序 |
| [Yap](https://github.com/FrigadeHQ/yap/tree/fbc46f72eaeba495deea98b1c1fc547ebcb0a2bc) | 原生 Swift/SwiftUI，MIT；**要求 macOS 26** | 先启动麦克风并缓存 buffer，再准备 SpeechAnalyzer；支持 partial | 仅 Apple SpeechAnalyzer 本地流式；不支持时拒绝，不偷偷上云 | 录音前锁定目标 App；剪贴板 session ID/changeCount；兼容 Electron 粘贴 | 一页式权限 onboarding、设置和 HUD | 状态机、首词防截断、目标 App 固定、剪贴板事务；ASR 本身不适合 RoType 的 macOS 14 基线 |
| [VoiceInk](https://github.com/Beingpax/VoiceInk/tree/fe27d8ae40a8775539f1f3ea09704ae0bb1c4bbe) | 原生 Swift/SwiftUI，**GPL-3.0** | 全局录音工作流 | provider registry 同时支持本地、云端、批量与流式 session | 带 session ID 的条件恢复 | 权限、麦克风、provider/model、API、体验引导 | registry、错误分类、pipeline 和成熟设置形状；**只借思想，不复制代码** |
| [Looped Whisper](https://github.com/loopedautomation/whisper/tree/cb2e4786172b89a3e4c532891799d4e2686dd362) | 原生 Swift/SwiftUI，MIT | PTT/toggle；Fn/Globe 单独走 event tap | WhisperKit 本地，录后识别；也有实时增量功能 | 固定目标 App 后插入 | 权限、模型、快捷键 | Fn 不能走普通注册快捷键的边界、标准热键兜底、目标窗口处理 |
| [VoiceScribe](https://github.com/eddmann/VoiceScribe/tree/d1e29a10d52913c67458d695d417517d17162d9a) | 原生 Swift + TCA，MIT | 固定全局热键，录后处理 | Whisper/Parakeet 本地，选配本地 LLM | copy/auto-paste | 模型、清理、偏好、历史；轻量状态浮窗 | 可测试 client seam，以及 `idle/recording/transcribing/cleaning/completed/error` 状态建模 |
| [Handy](https://github.com/cjpais/Handy/tree/fbd4e15fa14a721c66c57006ae110428b9e255b3) | Tauri/Rust，MIT | PTT/toggle/hybrid 单一状态机；VAD；处理按键重复、排队、Esc cancel | 多类本地 GGML 模型；流式/离线各有策略 | macOS paste transaction；文本/图片剪贴板恢复；多种投递方式 | 设置非常完整：设备、模型、VAD、提示、overlay、paste、后处理 | 产品能力基线和可靠性清单；不引入其跨平台框架，API key 存储方式也不能照搬 |
| [Whispering](https://github.com/EpicenterHQ/epicenter/tree/main/apps/whispering) | Svelte/Tauri，**AGPL-3.0** | 全局/焦点快捷键分层，拒绝保留键和冲突 | 本地、多云、自托管 provider；录音期间并行预热 | 显式 delivered/copied-fallback/failed | 分页设置、词典、状态 pill | typed errors、能力协商、预热、状态 UI；**仅概念重写** |
| [whisper.cpp](https://github.com/ggml-org/whisper.cpp) | C/C++，MIT | 示例直接采集 16 kHz mono | 本地流式，chunk + overlap + VAD | 不负责 macOS 全局输入体验 | 示例级 UI | 将来做本地实时字幕的底层基准；当前豆包 HTTP 版本不应先搬入其流式复杂度 |

补充排除项：存在一个同名 [vinkumdev/voiceink](https://github.com/vinkumdev/voiceink)，公开仓库只含说明并明确标注 proprietary，不是可复用源码。上表的 VoiceInk 指 `Beingpax/VoiceInk`，但其许可证是 GPL-3.0。

## 一、豆包接入：最值得直接转化的模式

### 1. Provider 必须是一等边界

SaidDone 将识别定义成只接受音频、语言提示并返回文本的 `ASRProvider`，本地与云端是并列实现：[Providers.swift](https://github.com/Chaoqi31/saiddone/blob/22edb02db96474b567556ab91fcb2ba601d3b39d/Sources/SaidDoneCore/Providers.swift#L3-L23)。Pindrop 的接口还暴露加载状态、进度和统一的 16 kHz mono Float32 输入：[TranscriptionEngine.swift](https://github.com/watzon/pindrop/blob/6668d098ac1e1594600d5fdd6c376a1f06aee9a7/Pindrop/Services/Transcription/TranscriptionEngine.swift#L21-L60)。

RoType 应采用：

```text
SpeechTranscribing
├── WhisperTranscriber       // 本地、离线
└── DoubaoSpeechTranscriber  // 云端、极速 HTTP
```

协议层还应提供 `validateConfiguration()` 或等价 readiness 状态，让设置界面的“测试连接”不需要知道具体供应商字段。

### 2. 豆包请求采用 WAV，而不是把 M4A 假设写死

SaidDone 的专用实现把音频编码成 base64 WAV，发送至极速识别 endpoint，并设置 `X-Api-App-Key`、`X-Api-Access-Key`、`X-Api-Resource-Id`、`X-Api-Request-Id`、`X-Api-Sequence`：[VolcengineASRProvider.swift](https://github.com/Chaoqi31/saiddone/blob/22edb02db96474b567556ab91fcb2ba601d3b39d/Sources/SaidDoneProviders/VolcengineASRProvider.swift#L31-L68)。它还区分 HTTP 错误和响应头中的业务状态码，把“未检测到语音”转为空结果：[同文件](https://github.com/Chaoqi31/saiddone/blob/22edb02db96474b567556ab91fcb2ba601d3b39d/Sources/SaidDoneProviders/VolcengineASRProvider.swift#L69-L104)。

建议 RoType 内部统一为 16 kHz mono PCM，豆包 adapter 输出 WAV；本地 Whisper 直接消费 PCM/临时 WAV。不要让 `AudioRecorder` 直接决定某一家 API 的上传格式。

### 3. 先做可验证的录后识别，预留 streaming session

当前产品交互是“按住说话、松开后插入”，豆包极速 HTTP 与此完全一致。VoiceInk 的 registry 证明批量服务和流式 session 可以共存于同一注册表：[TranscriptionServiceRegistry.swift](https://github.com/Beingpax/VoiceInk/blob/fe27d8ae40a8775539f1f3ea09704ae0bb1c4bbe/VoiceInk/Features/Recording/Workflows/TranscriptionServiceRegistry.swift#L13-L84)。因此第一版不应为了未来实时字幕提前引入 WebSocket，但协议命名不要锁死为“file uploader”。

将来需要实时文本时，再参考 whisper.cpp 的 [stream.cpp](https://github.com/ggml-org/whisper.cpp/blob/master/examples/stream/stream.cpp) 采用 chunk、overlap、VAD 的思路，并给本地/云端各自实现 streaming session。

### 4. 豆包测试不能只覆盖 200

SaidDone 使用注入的 `URLSession` + 自定义 `URLProtocol`，测试成功、嵌套响应、静音、业务错误、缺少凭据和 factory 路由：[VolcengineASRProviderTests.swift](https://github.com/Chaoqi31/saiddone/blob/22edb02db96474b567556ab91fcb2ba601d3b39d/Tests/SaidDoneProvidersTests/VolcengineASRProviderTests.swift#L5-L107)。RoType 至少应覆盖：

- 请求 header/body 正确，且日志不包含 Token 或音频；
- HTTP 401/403、超时、断网；
- HTTP 200 但业务码失败；
- 静音和空结果；
- 两种已观察到的响应 nesting；
- 任务取消；
- 用户明确开启时才回落本地 Whisper，并在 UI 告知实际使用的引擎。

## 二、录音、热键与文本插入

### 1. 用单一状态机承载 PTT/toggle，而不是堆事件判断

Handy 把 PTT、toggle、hybrid 放进一个协调器，统一处理 key-down、key-up、重复事件、忙碌排队和释放：[transcription_coordinator.rs](https://github.com/cjpais/Handy/blob/fbd4e15fa14a721c66c57006ae110428b9e255b3/src-tauri/src/transcription_coordinator.rs#L209-L250)。VoiceScribe 则把用户可见阶段拆成明确枚举：[PipelineFeature.swift](https://github.com/eddmann/VoiceScribe/blob/d1e29a10d52913c67458d695d417517d17162d9a/VoiceScribe/Shared/PipelineFeature.swift#L14-L47)。

RoType 第一版即使只开放 PTT，也应按完整生命周期实现；以后加 toggle 不需要重写 AppDelegate。需要包含 Esc 取消、转写期间防重入、录音开始/结束的短提示音开关。

Fn/Globe 不是普通快捷键：Looped Whisper 明确采用 passive event tap，并要求 Input Monitoring；标准组合键应保留为不需额外 Input Monitoring 的兜底：[README](https://github.com/loopedautomation/whisper/blob/cb2e4786172b89a3e4c532891799d4e2686dd362/README.md#L64-L79)。因此 RoType 可继续默认右 Option，Fn 作为高级选项，不要在引导中假装二者权限成本相同。

### 2. 首词不丢：先采集，再异步准备识别器

Yap 在准备 SpeechAnalyzer 之前先打开麦克风，通过 relay 暂存 buffer，识别器 ready 后再挂接，避免用户按下热键立即说话时丢掉开头：[DictationSession.swift](https://github.com/FrigadeHQ/yap/blob/fbc46f72eaeba495deea98b1c1fc547ebcb0a2bc/Sources/Services/DictationSession.swift#L63-L108)。其录音引擎还在每次开始时重建 graph，以处理输入设备采样率变化，并监听设备配置变化：[AudioCaptureService.swift](https://github.com/FrigadeHQ/yap/blob/fbc46f72eaeba495deea98b1c1fc547ebcb0a2bc/Sources/Services/AudioCaptureService.swift#L16-L49)。

豆包 HTTP 不需要边录边识别，但可以在录音期间完成配置校验、DNS/TLS 预热；本地 Whisper 则在录音期间预热模型。任何准备失败都不能阻塞录音线程。

### 3. 目标 App 和剪贴板都要有“所有权”

Yap 在展示自身 HUD 之前捕获 frontmost application，避免最终把文本贴回自己的窗口：[RecordingCoordinator.swift](https://github.com/FrigadeHQ/yap/blob/fbc46f72eaeba495deea98b1c1fc547ebcb0a2bc/Sources/Coordinator/RecordingCoordinator.swift#L108-L119)。其投递器保存剪贴板全部类型，写入本次 session ID，并且只有 changeCount 与 session ID 均未变化时才恢复，防止覆盖用户转写期间新复制的内容：[TextInjector.swift](https://github.com/FrigadeHQ/yap/blob/fbc46f72eaeba495deea98b1c1fc547ebcb0a2bc/Sources/Services/TextInjector.swift#L40-L93)、[同文件](https://github.com/FrigadeHQ/yap/blob/fbc46f72eaeba495deea98b1c1fc547ebcb0a2bc/Sources/Services/TextInjector.swift#L156-L208)。

RoType 应保留当前 AX/粘贴能力，但补上：

- 开始录音时固定目标 App；插入前必要时重新激活；
- 剪贴板保存所有 representation，不只保存字符串；
- 恢复前检查所有权，用户期间复制过内容则不恢复；
- Accessibility 缺失、Secure Input 或粘贴失败时，把结果留在剪贴板并明确显示“已复制，未自动插入”；
- Electron/Chromium 使用经过实测的短延迟，不将“发出 Cmd-V”当成“插入成功”。

## 三、界面与首次配置

### 首次引导建议为六步

1. **欢迎与隐私选择**：本地 Whisper / 豆包云端并列；豆包旁明确“录音会上传”。
2. **系统权限**：麦克风、Accessibility；选择 Fn 时才出现 Input Monitoring。回到应用时自动刷新权限状态。
3. **语音服务**：豆包 App ID、Access Token、Resource ID；Token 为 SecureField，保存至 Keychain。
4. **连接与准备**：豆包“测试连接”；本地则检查/下载/预热模型，并区分 Downloading 与 Preparing。
5. **热键和行为**：右 Option 默认；PTT/toggle；提示音；失败是否回落本地。
6. **试说一句**：真实录音、识别、显示结果，但不向其他 App 注入；通过后完成。

SaidDone 的 onboarding 把语言、欢迎、权限、引擎、准备、试用、完成显式建模，并对下载/云测试/预热分别提供进度：[Onboarding.swift](https://github.com/Chaoqi31/saiddone/blob/22edb02db96474b567556ab91fcb2ba601d3b39d/Sources/SaidDoneApp/Onboarding.swift#L6-L71)。Yap 的权限页会在应用重新获得焦点时刷新，不要求重启：[OnboardingView.swift](https://github.com/FrigadeHQ/yap/blob/fbc46f72eaeba495deea98b1c1fc547ebcb0a2bc/Sources/Views/OnboardingView.swift#L19-L96)。

### 日常设置建议

- **语音**：豆包/本地、语言自动检测、自动标点、降级策略、输入设备、测试按钮。
- **快捷键**：触发键、PTT/toggle、冲突校验、Esc 取消、提示音。
- **双语候选**：动态翻译开关、英文候选位置（默认 9）、全拼/双拼说明。
- **隐私与诊断**：当前处理位置、清除 Token、权限状态、最近一次错误（脱敏）、打开日志。

不要把 base URL、Resource ID 等高级字段与用户第一眼最需要的“App ID + Token + 测试”混在同一层；高级字段折叠显示。也不要像某些项目一样默认保存全部转写历史，RoType 的隐私定位更适合默认不留历史。

## 四、凭据、隐私和许可边界

SaidDone 将非敏感设置原子写入 JSON，把 ASR key 单独写入 Keychain，并支持从旧明文配置迁移：[Config.swift](https://github.com/Chaoqi31/saiddone/blob/22edb02db96474b567556ab91fcb2ba601d3b39d/Sources/SaidDoneCore/Config.swift#L300-L389)。Pindrop 同样把 provider 普通配置与 Keychain secret 分离：[AIConfigurationV2.swift](https://github.com/watzon/pindrop/blob/6668d098ac1e1594600d5fdd6c376a1f06aee9a7/Pindrop/Services/AIConfigurationV2.swift#L7-L20)。

RoType 的存储边界应是：

```text
UserDefaults / plist: provider、App ID、Resource ID、语言、热键、fallback 开关
macOS Keychain:        豆包 Access Token
不持久化:             原始音频、请求 body、完整转写结果
```

许可证处理：

- SaidDone、Pindrop、Yap、Looped Whisper、VoiceScribe、Handy、whisper.cpp 为 MIT。若复制实质代码，发行物中必须保留对应版权和许可声明；更稳妥的方式仍是按 RoType 接口自行实现并在文档致谢。
- VoiceInk 是 GPL-3.0，Whispering 是 AGPL-3.0，Speech Note 是 MPL-2.0，nerd-dictation 是 GPL 系列。除非明确接受相应 copyleft 义务，否则只借架构思想，不逐段复制。
- Handy 的名称、Logo 和图标不属于其 MIT 品牌授权范围，不能沿用。

## 五、不应融合的反模式

1. **在 AppDelegate 内判断 URL host 来选择 provider**：短期省事，长期会把 UI、配置和协议耦合；应使用显式 `VoiceProvider` enum/factory。
2. **云端失败后静默换本地**：用户无法判断结果来源，首次本地模型冷启动还会像卡死。fallback 必须可配置并反馈。
3. **在 UserDefaults、JSON 或日志保存 Token**：Handy/Whispering 的部分实现不符合 RoType 的 macOS 隐私标准。
4. **先初始化模型、后开麦克风**：会截掉第一句话开头。
5. **盲目延时后恢复剪贴板**：会覆盖用户新复制的内容；必须检查 changeCount/session ownership。
6. **发出 Cmd-V 即宣告成功**：Secure Input、权限、Electron 异步读取都会造成假成功。
7. **第一版就上流式 WebSocket/VAD/增量替换**：与“松开后插入”的当前验收无关，扩大状态和错误面。
8. **为借鉴 Handy/Whispering 引入 Tauri 前端**：RoType 已有 Swift/AppKit/SwiftUI 进程，新增 runtime 只会增加包体、权限和发布复杂度。
9. **默认保存语音历史**：与“本地优先、最少留存”定位冲突；若以后添加，必须显式开启并提供一键清理。

## 建议的落地优先级

```text
P0  SpeechTranscribing + Doubao adapter + Keychain + mock tests
P0  录音/转写/插入显式状态 + 脱敏错误
P0  设置页：凭据、测试连接、云端说明、fallback
P1  首次六步引导 + 试说一句
P1  目标 App 固定 + 剪贴板所有权恢复 + copied fallback
P1  快捷键冲突检测、Esc 取消、toggle 模式
P2  输入设备切换、VAD、预热优化
P3  豆包流式 session / 实时 partial（有明确需求后再做）
```

这套融合保持 RoType 的原生 Swift 结构：吸收成熟项目已经踩过的坑，但不把另一个应用的框架、数据模型或许可证一起搬进来。
