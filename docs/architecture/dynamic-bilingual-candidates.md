# 任意输入的动态双语候选：可落地架构调研

更新日期：2026-09-01

> 历史调研，不是当前实现规范。活动路径现为独立译文栏与 v2 XPC，旧响应文件/F18/编号译文已清退。参见 [候选合约](candidate-translation-contract.md) 与 [兼容说明](legacy-translation-retirement.md)。

> 实施更新（0.2.25）：Phase 2 已采用 Squirrel 薄适配层完成，而非单独的 native librime plugin。Lua 通过 session property 提供候选语义，Squirrel 使用按签名角色授权的 Mach XPC 与独立 Translation worker 通信，并在所属 controller 内刷新 composition。请求具备随机 session token、单调 generation、取消、超时和重连；Secure Input 启用时不请求翻译或写入缓存；响应文件权限为 `0600`，父目录为 `0700`。worker 还记录真实 controller 按键的单调 generation，设置 helper 只能查询该证据，分布式通知只作为无权威性的刷新提示。当前 Apple Translation 实现需要 macOS 26，macOS 14-15 的 CTranslate2 fallback 与持久翻译缓存仍是非目标。

## 结论

RoType 当前 Lua 实现是一个小型双向词表，只能证明“翻译结果可以作为独立 Rime 候选被选择”，不能满足“任意中文/英文输入都能得到翻译”。要满足该目标，不能继续靠扩充静态词表；需要把 Rime 的候选管线接到一个常驻、异步、带缓存的本地翻译后端。

推荐采用以下分层方案：

1. 保留 Rime 原候选作为永不阻塞的主路径。
2. 新增 macOS 专用 `librime` 原生插件，读取缓存、发起异步翻译，并在结果返回后安全触发当前 composition 重算。
3. 翻译后端放在独立 Swift helper/XPC service 中：macOS 15+ 优先 Apple Translation；macOS 14 或系统语言包不可用时回退到 CTranslate2 + OPUS-MT 中英模型。
4. 热缓存命中时翻译候选随首屏一起出现；冷请求时原候选先在 50 ms 内出现，翻译候选稍后原位刷新。不能让神经机器翻译阻塞按键线程。

纯 Lua 可以做缓存命中和原型验证，但不能可靠地独立完成“异步请求结束后自动刷新候选”。真正上线不必全面 fork Squirrel，不过需要原生插件负责异步生命周期；若插件无法在 Squirrel 的主输入线程安全调度刷新，则只给 Squirrel 增加一个很薄的 refresh bridge。

## 目标语义先钉死

“所有输入都能有”应定义为：任意可翻译的完整中文或英文词/短语，都能产生至少一个反向语言候选；不是要求把首屏所有中文候选逐个翻译。

以截图中的 `nizaiganma` 为例：

- Rime 先正常给出“你在干吗”等中文候选。
- RoType 对排名第一的完整中文候选“你在干吗”发起中译英。
- 缓存命中则立即插入 `What are you doing?〔中→英〕`；冷请求则先显示中文，翻译完成后刷新候选并插入。
- 如果用户把高亮移动到另一个中文候选，可按需翻译当前高亮候选；默认不要同时翻译 9 个候选。

英文方向直接使用已完成的英文 composition（例如 `what are you doing`）作为源文本，插入 `你在做什么？〔英→中〕`。所有翻译候选都必须保留自己的源文本快照和请求代号，旧请求返回时不得污染新 composition。

## Rime / Lua 的能力边界

### 已确认能做的

- `librime-lua` 的 translator/filter 用 Lua coroutine 包装；Lua 函数通过 `yield(candidate)` 逐项产生候选。[Lua translator 实现](https://github.com/hchunhui/librime-lua/blob/master/src/lua_gears.cc) / [官方示例](https://github.com/hchunhui/librime-lua/blob/master/sample/lua/date.lua)
- Lua 暴露了 `Context.refresh_non_confirmed_composition()`，也暴露 context 的 update/option/property notifier。[类型绑定](https://github.com/hchunhui/librime-lua/blob/master/src/types.cc)
- `librime` 在 composition 更新时同步执行 segmentation 和 translation；`RefreshNonConfirmedComposition()` 会清除未确认分段并触发 update notifier，随后 engine 重新 compose。[Context 实现](https://github.com/rime/librime/blob/master/src/rime/context.cc) / [Engine 实现](https://github.com/rime/librime/blob/master/src/rime/engine.cc)

### 不能据此推导出的能力

Lua 的 `yield` 是候选枚举用的 coroutine yield，不是可以等待 HTTP/XPC 后在未来任意时刻恢复的异步任务。`LuaTranslation::Next()` 在候选枚举期间同步 `resume` coroutine；源码没有任务调度器、Promise、socket event loop 或线程切换机制。[LuaTranslation 实现](https://github.com/hchunhui/librime-lua/blob/master/src/lua_gears.cc)

因此：

- 在 Lua translator/filter 里同步调用翻译服务会直接增加按键和候选延迟，不可接受。
- Lua 可以快速读取已有缓存，或者把请求写入外部队列；但结果回来后，如果用户没有继续按键，纯 Lua 没有可靠的唤醒入口。
- 从后台线程直接调用 Lua state 或 `Context.refresh_non_confirmed_composition()` 不安全；`librime-lua` 源码没有为 Lua state 或 Context 提供跨线程安全保证。
- `set_property` 本身只发消息，不会重算 composition；`set_option` 在 composing 时会调用 refresh，但仍必须从正确的输入线程调用。[Engine 的 option/property 处理](https://github.com/rime/librime/blob/master/src/rime/engine.cc)

结论是：缓存命中路径可以继续用 Lua；完整异步闭环需要原生代码和明确的主线程调度点。

## 四种方案

### 方案 A：继续扩充离线词典

结构：Rime 字典/Lua 哈希表直接查中英映射。

优点：

- 延迟最低、实现最小、完全离线。
- 候选天然是同步且可选择的。

缺点：

- 永远无法覆盖任意短语、句子、新词和上下文歧义。
- 双向维护、词形变化、专有名词和一词多义会迅速失控。

适用：只作为高频热词层和离线兜底，不是最终方案。

### 方案 B：纯 Lua + 外部 helper + 缓存

结构：Lua 对缓存命中直接 yield；未命中时把请求交给本地 helper，结果写回 SQLite/共享缓存。下一次按键重新查询时显示翻译。

优点：

- 不需要自编译 Squirrel/librime，最快能做出技术验证。
- 能验证候选排序、缓存键、取消旧请求和后端质量。

缺点：

- 冷请求结束时不能可靠地自动刷新；用户可能必须再按一个键。
- Lua 若用 `io.popen`、同步 HTTP 或阻塞 socket，会卡住输入线程。
- 文件轮询/频繁 SQLite 打开会带来不可控尾延迟。

结论：适合一周内的 spike，不满足最终验收。

### 方案 C：原生 librime 插件 + Swift 翻译服务 + 薄刷新桥（推荐）

结构：

```text
按键 → Rime 原候选（立即）
              ↓ top/current source candidate
       native bilingual filter/translator
          ├─ LRU/SQLite 命中 → yield 翻译候选
          └─ 未命中 → 异步 XPC 请求 → Swift Translation Service
                                      ├─ Apple Translation（macOS 15+）
                                      └─ CTranslate2 + OPUS-MT（macOS 14/fallback）
                       结果返回 → 主输入线程 refresh composition → 缓存命中 → 新候选
```

原生 filter 负责中文方向：观察合并后的中文候选，只翻译 top-1 或当前高亮项；英文 translator 负责英文方向：翻译完整英文 composition。插件只在缓存命中时产出候选，所有模型推理都在 helper 内执行。

刷新有两种实现顺序：

1. 先尝试插件内部通过 macOS 主队列调度，并用可取消、受生命周期保护的 engine/context 句柄调用 `RefreshNonConfirmedComposition()`。
2. 如果 Squirrel 的实际线程模型无法给出可验证的安全性，就给 Squirrel 增加一个很薄的桥：helper 结果通知到达 Squirrel 后，由 Squirrel 的输入主线程切换一个内部 option 或调用 refresh。这个补丁只负责“唤醒重算”，不把翻译逻辑塞进 Squirrel。

优点：

- 保留 Rime 词库、模糊音、双拼和候选排序能力。
- 冷请求不阻塞按键；结果可以自动出现。
- 后端可替换，Apple Translation、OPUS-MT、本地 LLM 或可选云服务共享同一接口。

缺点：

- 需要维护 macOS arm64 的 librime plugin 构建、签名和 Squirrel 兼容矩阵。
- 必须认真处理 session 销毁、请求取消、线程归属和候选刷新抖动。

结论：这是满足 PRD 且维护边界最清晰的路线。

### 方案 D：fork Squirrel，在前端直接拼接候选

结构：Squirrel 获得 Rime 菜单后直接调用翻译服务，把翻译项绘制到候选窗，并自行处理数字键/鼠标选择与 commit。

优点：

- Swift async/await、Apple Translation、XPC 和 UI 刷新都更自然。
- 不需要在 librime 内解决跨线程唤醒。

缺点：

- Squirrel 前端必须重写候选索引、翻页、选择、提交和高亮同步。
- 容易造成“画面里是一个候选，Rime 认为是另一个候选”的状态分裂。
- 长期跟进 Squirrel 上游的成本最高。

结论：只有在方案 C 的安全刷新桥无法收敛时才采用；不要一开始就全面 fork。

## 翻译后端评估

### Apple Translation：macOS 15+ 首选

Apple Translation framework 从 macOS 15.0 / iOS 18.0 起可用；Apple 的 WWDC24 示例要求 Xcode 16，并介绍了 macOS 支持。[WWDC24: Meet the Translation API](https://developer.apple.com/videos/play/wwdc2024/10117/) / [Apple 示例](https://developer.apple.com/documentation/translation/translating-text-within-your-app)

关键能力：

- `TranslationSession.translate` 是 async API，支持单条和批量翻译。[TranslationSession](https://developer.apple.com/documentation/translation/translationsession)
- 翻译内容在设备上处理。Apple 说明可能收集 bundle ID、源/目标语言等使用与性能指标，但不收集原文和译文。[TranslationSession 注记](https://developer.apple.com/documentation/translation/translationsession)
- `LanguageAvailability` 可查询支持语言和语言对处于 installed/supported/unsupported 的状态。[LanguageAvailability](https://developer.apple.com/documentation/translation/languageavailability)
- 无 UI 的 `init(installedSource:target:)` 只可使用已经安装的语言；缺少语言包会抛错。请求下载权限要通过带 UI 的 `translationTask`/`prepareTranslation` 流程完成。[installedSource initializer](https://developer.apple.com/documentation/translation/translationsession/init%28installedsource%3Atarget%3A%29) / [prepareTranslation](https://developer.apple.com/documentation/translation/translationsession/preparetranslation%28%29)

限制：

- 不支持 macOS 14，所以不能是唯一后端。
- 语言包由系统管理，首次准备必须有一个用户可见的 companion UI；输入法进程里静默下载不可取。
- Apple 不承诺每条翻译 50 ms 内完成，因此仍需异步和缓存。

### CTranslate2 + OPUS-MT：macOS 14 的推荐本地兜底

CTranslate2 是面向生产的 C++ Transformer 推理引擎，支持 encoder-decoder 模型（含 Marian/OPUS-MT、NLLB），提供并行/异步翻译、量化、ARM64，以及 Apple Accelerate CPU backend。[CTranslate2 README](https://github.com/OpenNMT/CTranslate2) / [异步 Translator API](https://github.com/OpenNMT/CTranslate2/blob/master/include/ctranslate2/translator.h) / [硬件支持](https://github.com/OpenNMT/CTranslate2/blob/master/docs/hardware_support.md)

中英双向可从 `Helsinki-NLP/opus-mt-zh-en` 与 `Helsinki-NLP/opus-mt-en-zh` 起步；OPUS-MT 官方仓库提供可下载模型并说明模型许可，具体发行包仍需逐个固定版本和核对 license/attribution。[OPUS-MT](https://github.com/Helsinki-NLP/Opus-MT) / [en→zh 模型卡](https://huggingface.co/Helsinki-NLP/opus-mt-en-zh) / [zh→en 模型卡](https://huggingface.co/Helsinki-NLP/opus-mt-zh-en)

建议：

- helper 启动时常驻加载两个方向的 int8 模型。
- 短候选用 `beam_size=1`，不返回 score；CTranslate2 官方也把 greedy/beam 1 列为性能优化项。[性能建议](https://opennmt.net/CTranslate2/performance.html)
- 首次安装模型必须展示大小、来源、校验和与许可证；下载后完全离线。
- 在目标 M1/M2/M3/M4 机器实测 P50/P95、首包冷启动和常驻内存后再定具体模型版本，不能用框架能力代替产品基准。

这是比通用 LLM 更适合输入法候选的第一版后端：模型小、输出短、解码可控、无思考文本，且 C++/Swift helper 边界清楚。

### NLLB：多语扩展候选，不建议当前中英首发

NLLB-200 distilled 600M 支持大量语言，Transformers 有标准翻译用法，CTranslate2 也原生列出 NLLB 支持。[Transformers NLLB 文档](https://github.com/huggingface/transformers/blob/main/docs/source/en/model_doc/nllb.md) / [CTranslate2 支持模型](https://github.com/OpenNMT/CTranslate2)

但 600M 模型原始权重约 2.5 GB，且模型卡是 CC-BY-NC-4.0；这对后续分发和商业使用是明确约束。[NLLB 模型卡](https://huggingface.co/facebook/nllb-200-distilled-600M)

结论：等产品扩展到 3 种以上语言再评估，不应为中英双向首版增加体积和许可风险。

### MLX / llama.cpp / Qwen：作为可选“高质量润色”，不是首屏热路径

- Apple 的 MLX/MLX-LM 专为 Apple Silicon，提供模型量化、本地生成和带 prompt cache 的 server；适合常驻通用模型。[MLX-LM](https://github.com/ml-explore/mlx-lm) / [server prompt cache 实现](https://github.com/ml-explore/mlx-lm/blob/main/mlx_lm/server.py)
- llama.cpp 在 Apple Silicon 上支持 Metal，并提供 OpenAI-compatible 本地 HTTP server。[llama.cpp](https://github.com/ggml-org/llama.cpp) / [server](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)
- Qwen3 有开放权重的小模型，可通过上述运行时做通用翻译；但专门的 Qwen-MT 官方发布目前是 API 产品，官方用法指向 DashScope，不是可捆绑的本地权重。[Qwen-MT 官方说明](https://qwenlm.github.io/blog/qwen-mt/) / [Qwen3](https://github.com/QwenLM/Qwen3)

通用 decoder-only LLM 的常驻内存、首 token 延迟、输出约束和模型体积通常都高于专用 Marian 模型。它适合：用户已运行本地模型时提供第二翻译、长句润色或领域术语增强；不适合把每次键盘 composition 都发给它。

### WhisperKit / whisper.cpp：只属于语音链路

Whisper 是音频到文本/英语翻译模型，不是文本到文本双向翻译器。OpenAI 明确说明 `translate` 任务是非英语语音到英语，不能把它当候选翻译后端。[Whisper README](https://github.com/openai/whisper) / [Whisper decoding options](https://github.com/openai/whisper/blob/main/whisper/decoding.py)

WhisperKit 和 whisper.cpp 都适合 RoType Voice 的本地 ASR：WhisperKit 原生面向 Apple Silicon/Core ML；whisper.cpp 支持 Apple Silicon Metal。但它们不能解决英译中键盘候选。[WhisperKit](https://github.com/argmaxinc/WhisperKit) / [whisper.cpp](https://github.com/ggml-org/whisper.cpp)

## 性能与缓存设计

“候选延迟 < 50 ms”要拆成两个指标：

- Rime 原候选首帧：P95 < 50 ms，任何翻译故障都不能影响。
- 翻译候选：热缓存 P95 < 10 ms；冷请求采用渐进刷新，先通过真机 benchmark 再确定 SLO。不能承诺所有任意文本的冷 NMT 都小于 50 ms。

建议机制：

1. 仅当 composition 在 100–150 ms 内无新按键、已形成完整英文词/短语，或中文 top candidate 稳定时请求。
2. 每个 session 只有一个最新 generation；新按键立即取消/废弃旧 generation。
3. 两层缓存：插件内 LRU（零 IPC 热路径）+ helper SQLite（跨进程/重启）。
4. 缓存键至少包含 `sourceLanguage + targetLanguage + exactSource + backendID + modelVersion + optionsHash`；大小写和标点可能影响译文，不做激进归一化。
5. 只请求 top-1；用户移动高亮后再请求该项。允许配置 top-N，但默认最多 2，避免放大计算量和候选抖动。
6. helper 启动预热 tokenizer/model；安装后做一次无内容健康检查，不在首次按键时加载数百 MB 模型。
7. 失败、未安装语言包、超时或模型不可用时只隐藏翻译候选，不影响 Rime 原候选和上屏。

必须采集本地、无原文的性能指标：请求方向、字符桶、cache hit、backend、排队时间、推理时间、刷新时间、取消原因。默认不得记录输入原文或译文。

## 隐私与安全边界

- 默认后端只能是 Apple on-device Translation 或本地模型；云翻译必须由用户显式开启并在候选上标识。
- helper 只监听 XPC 或权限为 0600 的 Unix domain socket，不开放局域网 TCP 端口。
- 每个请求必须带随机 session ID 和单调 generation；worker 按代码签名角色授权操作，返回结果时由 controller 校验方向、exact source、composition 和 generation。
- SQLite 缓存默认可关闭、可一键清空，并设置容量/TTL；密码框和 secure input 场景完全禁用翻译与持久缓存。
- 模型下载固定 URL、版本、SHA-256 和许可证；禁止运行模型仓库里的任意 remote code。
- 使用 Apple Translation 时，隐私说明应准确写明：内容在设备处理；Apple 可能收集不含原文/译文的 API 使用和性能元数据，而不是宣称“绝对无任何数据”。

## 推荐分阶段路线

### Phase 0：把当前能力诚实标为 demo

- UI/README 将现有 10 对词改称“静态词表演示”，不要再按 PRD 完成验收。
- 固化动态候选接口：`request(source, sourceLang, targetLang, generation)`、`cachedResult`、`cancel`、`resultAvailable`。

### Phase 1：纯 Lua + helper spike

- 用 Swift helper 做 Apple Translation（macOS 15+）和一个假的延迟后端。
- Lua 只验证缓存命中、候选插入位置、top-1 语义和 stale result 丢弃。
- 明确记录“冷结果需下一键刷新”的缺口；此阶段不发布为完成版。

退出标准：任意 100 条中英文测试短语在 helper 内都可返回；Rime 原候选 P95 不退化；缓存键和 stale-result 测试通过。

### Phase 2：原生插件闭环

- 实现 native filter/translator、LRU、异步 XPC、取消和主输入线程 refresh。
- 先在未改 Squirrel 的构建中验证主队列调度；若线程/生命周期证据不足，再加薄 Squirrel refresh bridge。
- 加入 macOS 14 的 CTranslate2 + OPUS-MT fallback，并做模型管理 UI。

退出标准：停止输入后无需再按键，冷翻译可自动出现；快速连续输入不会显示旧译文；数字键和鼠标选择正确上屏；TextEdit、Safari、VS Code、微信等真实 App 通过。

### Phase 3：质量与可选增强

- 术语表和用户翻译记忆优先于模型。
- 可选本地 LLM 第二候选/润色，永不替换专用 MT 的快速候选。
- 只有在产品需要多语种时再评估 NLLB，并先解决模型许可和体积。

## 决策

建议立即停止“补词表”的方向，进入方案 C。第一版动态后端组合是：

- macOS 15+：Apple Translation，用户在 companion UI 中预装中英语言包。
- macOS 14 或 Apple 后端不可用：CTranslate2 + 固定版本的 OPUS-MT zh-en/en-zh int8 模型。
- 高频静态词典：继续保留，作为零延迟覆盖层和术语覆盖层。
- 通用本地 LLM：只做可选增强，不进入默认按键热路径。

这条路线既能兑现“任意输入都有翻译”，也能保住 Rime 原候选的响应速度、离线隐私和后端可替换性。
