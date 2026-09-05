# macOS 中文语音输入 ASR 选型（2026-09）

## 实施决策更新（0.2.25）

在 Apple Silicon 真实加载、中文转写和产品体积取舍验证后，产品选择 Qwen3-ASR 双档方案：0.6B 作为默认推荐下载，1.7B 作为高精度可选下载。两者均由独立的洛克语音进程通过 MLX/Metal 加载；输入法设置只承担显式下载、选择和模型状态管理。以下 SenseVoice 结论保留为初始调研记录，不再代表当前实施方案。

## 结论

RoType 旧语音 App 固定使用 `openai_whisper-base`。该模型只适合轻量级验证，不应作为中文语音输入的质量基线。

当前采用：

1. 默认推荐模型：**Qwen3-ASR-0.6B**，固定 revision，约 1.88 GB 下载。
2. 高精度模型：**Qwen3-ASR-1.7B**，固定 revision，约 4.70 GB 下载。
3. 两档模型均不随安装包分发，也不会因启动服务或提交转写而自动下载。
4. SenseVoiceSmall + sherpa-onnx 保留为后续原生 runtime 对照项；WhisperKit 不作为中文最佳引擎。

语音采集、模型下载、ASR 和跨 App 写入应继续放在独立、用户显式启动的语音 App 中，不应重新并入 IMK 输入法或动态翻译 worker。

## 候选对比

| 方案 | 中文质量 | macOS 产品化 | 体积/成本 | 许可证 | 判断 |
|---|---|---|---|---|---|
| Qwen3-ASR-1.7B | 官方公开表中总体最强；WenetSpeech net/meeting WER 4.97/5.88，AISHELL-2 2.71 | 官方高性能流式路径依赖 vLLM；原生 MLX 主要是社区实现 | 官方 safetensors 约 4.7 GB | Apache-2.0 | 准确率上限，不适合默认常驻 |
| Qwen3-ASR-0.6B | 同一公开表中 WenetSpeech 5.97/6.88，AISHELL-2 3.15 | 与 1.7B 相同，需验证社区 MLX runtime | 明显小于 1.7B | Apache-2.0 | 值得做高精度本地原型 |
| SenseVoiceSmall | 官方项目称中文、粤语优于 Whisper；支持中/英/粤/日/韩 | sherpa-onnx 支持 macOS、Swift、离线 ASR；工程路径成熟 | 官方 `model.pt` 约 936 MB，可使用 ONNX/int8 | FunASR Model License，官方说明允许商用但需归属和命名 | **默认推荐** |
| WhisperKit large-v3-turbo | 显著优于当前 base，但不是中文专用 SOTA | Core ML/Apple Silicon 集成最成熟 | 官方压缩版本约 626 MB | Whisper 权重 MIT；WhisperKit MIT | 兼容后端/快速止血 |
| WhisperKit base | 当前旧实现 | 已能运行 | 小 | MIT | 淘汰 |

不同项目的指标并非都使用同一推理设置，不能横向拼成一个绝对排行榜。上线判断必须使用同一批 RoType 真实录音做 CER、首字延迟、整句延迟、峰值内存和功耗对比。

## Qwen3-ASR

Qwen 官方仓库发布 0.6B 和 1.7B 两档，支持 30 种语言和 22 种中文方言，并提供 offline/streaming 统一模型。官方公开基准中，1.7B 在列出的中文普通话、粤语和方言数据集上明显优于 Whisper large-v3，并多数优于表中的商业 API。模型卡采用 Apache-2.0。

问题在 runtime：官方推荐的高性能和流式实现是 vLLM；这不是 macOS App 可直接内嵌的部署形态。`mlx-qwen3-asr` 等 Apple Silicon 项目是社区移植，成熟度、量化误差、流式状态和长期维护都需要独立验收。因此不能只因模型榜单最好就直接替换生产引擎。

## SenseVoiceSmall + sherpa-onnx

SenseVoiceSmall 是面向普通话、粤语、英语、日语和韩语的非自回归模型。官方项目报告它在中文和粤语公开数据集上优于 Whisper，并在其测试设置下比 Whisper-Small 快 5 倍以上、比 Whisper-Large 快 15 倍以上。

`sherpa-onnx` 提供 macOS、arm64、Swift、流式/离线 ASR，并正式列出 SenseVoice 部署。这使录音、VAD、推理和 Swift App 集成可以保持在本地原生进程，不要求 Python server。模型权重不是标准 Apache/MIT，而是 FunASR Model Open Source License；官方维护者说明允许商用，但需要遵守 attribution 和模型命名条款。发布前仍需把固定版本的模型许可证随 App 分发。

## WhisperKit

Argmax 官方当前建议 `large-v3-v20240930_626MB` 用于 iOS/macOS 最高多语准确率，macOS 可使用未压缩 turbo 版本追求速度和准确率。它是当前改造成本最低的方案：旧代码只需更换模型、固定语言为中文并完善 VAD/解码参数。

但旧实现的问题不只是模型大小：它没有显式中文语言提示、没有领域热词、没有可靠 VAD/增量稳定策略，也没有使用 large-v3-turbo。因此“仅换模型”可以明显改善，却不能达到中文专用模型的上限。

## 产品实施顺序

1. 建立 50-100 条真实中文录音集，包含口语、专有名词、中英混说、安静/噪声和不同麦克风。
2. 统一输出标准化规则，分别测 SenseVoiceSmall、Qwen3-ASR-0.6B、Qwen3-ASR-1.7B 和 WhisperKit large-v3-turbo。
3. 指标至少包含 CER、专有名词召回、首字延迟、句末延迟、峰值内存、模型下载大小和 10 分钟持续功耗。
4. 默认推荐 Qwen3-ASR-0.6B，高精度档使用 1.7B；模型通过固定 repository revision 下载，并以完成标记和权重文件校验约束可用状态。
5. 语音 App 使用独立 Bundle ID、按需运行、明确麦克风权限；不恢复旧 RunAtLoad LaunchAgent。
6. 模型和用户词典提供可见的下载、删除、容量和版本状态。
7. 任何云端 ASR 必须显式 opt-in，并在录音前说明音频会离开设备。

## 一手来源

- Qwen3-ASR 官方仓库、功能和公开基准：https://github.com/QwenLM/Qwen3-ASR
- Qwen3-ASR 0.6B 模型卡（Apache-2.0）：https://huggingface.co/Qwen/Qwen3-ASR-0.6B
- Qwen3-ASR 1.7B 模型卡（Apache-2.0）：https://huggingface.co/Qwen/Qwen3-ASR-1.7B
- SenseVoice 官方仓库、基准和许可证说明：https://github.com/FunAudioLLM/SenseVoice
- SenseVoiceSmall 模型卡：https://huggingface.co/FunAudioLLM/SenseVoiceSmall
- sherpa-onnx 官方仓库、平台和 Swift 支持：https://github.com/k2-fsa/sherpa-onnx
- sherpa-onnx SenseVoice 部署文档：https://k2-fsa.github.io/sherpa/onnx/sense-voice/index.html
- WhisperKit 官方模型选择说明：https://github.com/argmaxinc/WhisperKit#model-selection
