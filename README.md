# RoType

RoType 是一个面向 macOS 的双向双语键盘和本地语音输入法实验项目。Rime 负责原始输入候选，RoType Voice 负责异步本地翻译、候选刷新和语音转写。

本仓库同时维护基于 Squirrel 1.1.2 的 GPL v3 前端修改。RoType 的翻译与语音入口直接出现在输入法菜单中，RoType Voice 作为无菜单栏图标的本地后台服务运行。

## 当前已实现

- 中文拼音先产生正常 Rime 候选，再把首选中文交给 Apple Translation；翻译完成后自动刷新并插入独立英文候选。
- 英文单词可直接翻译；英文短语使用单引号代替 composition 内的空格，例如 `what'are'you'doing`。
- 动态结果严格匹配当前原始输入和首选候选；继续输入后，旧翻译不会混入新候选。
- Rime 输入线程只读写小型本地交换文件，模型推理在 RoType Voice 中异步执行。
- 通过 Squirrel 自带的 Luna Pinyin 词库提供完整全拼中文候选。
- 提供独立的“RoType 小鹤双拼”方案，双拼编码同样保留双向翻译候选。
- 保留 10 组人工校准词条作为零延迟热词，不再把静态词表当作通用翻译方案。
- 右 Option 按住录音、松开后由 WhisperKit 本地转写。
- 录音中、转写中、完成和错误状态浮层。
- 通过 macOS 辅助功能权限向当前标准编辑控件发送 Unicode 文本。

中文全拼候选来自 Luna Pinyin。动态翻译当前使用 macOS 26 的无界面 `TranslationSession`；macOS 15 可以准备系统语言包，但 macOS 14–15 的 CTranslate2 本地模型兜底尚未实现。密码框和 macOS Secure Input 不在支持范围内。

## 环境

- macOS 14+（语音和基础 Rime）；动态 Apple Translation 当前需要 macOS 26+
- Apple Silicon 优先
- Xcode 16+
- Squirrel（当前正式发行包包含 librime-lua 和 Luna Pinyin 词库）
- 首次使用 WhisperKit 时下载多语言 `openai_whisper-base` 模型；模型路径会保存在 `~/Library/Application Support/RoType/WhisperModels`，后续显式从本地目录离线打开

## 验证 Rime 方案

1. 安装 Squirrel。
2. 执行 `./scripts/install-rime.sh`。
3. 从 Squirrel 菜单选择“重新部署”。
4. 选择“RoType 双向双语”全拼方案，或“RoType 小鹤双拼”方案。
5. 启动 RoType Voice，从菜单选择“准备中英翻译语言包…”，按系统提示安装语言包。
6. 全拼输入 `nizaiganma`，等待英文翻译候选自动出现；输入 `computer` 或 `what'are'you'doing` 验证英文到中文。

RoType 中文候选使用鼠须管随包提供的完整朙月拼音词库和八股文语言模型，并保留用户词频学习。全拼与小鹤双拼默认启用 `zh/z`、`ch/c`、`sh/s`、`n/l`、`en/eng`、`in/ing` 常用模糊音；全拼另外支持简拼、拼写纠错和常见按键纠错。

安装脚本只覆盖同名 RoType 文件，并在 `~/Library/Rime/rotype-backups/` 保存已有同名文件。若已经存在 `default.custom.yaml`，脚本不会覆盖它，而会提示手工将 `rotype` 和 `rotype_flypy` 加入 `patch/schema_list`。

## 构建语音助手

```sh
./scripts/build-app.sh
open "dist/RoType Voice.app"
```

首次启动需要允许麦克风、输入监控和辅助功能权限。辅助功能同时用于在异步翻译完成后发送一个只由 RoType 消费的候选刷新事件。打开任意普通文本编辑框，按住右 Option 说话，松开后等待文字插入。

## 测试

```sh
./scripts/test.sh
```

Lua 测试验证请求投递、动态候选插入、过期结果隔离和刷新事件；Swift 测试验证交换协议及 Unicode 文本分块。测试通过不代表 InputMethodKit、系统语言包、麦克风权限和目标 App 已完成真实验收。

若已有解包后的官方 `Squirrel.app`，还可以运行真实 Rime 部署测试：

```sh
ROTYPE_SQUIRREL_APP="/path/to/Squirrel.app" ./scripts/test-rime-deploy.sh
```

## 当前非目标

- macOS 14–15 的 CTranslate2 + OPUS-MT 本地翻译兜底
- 小鹤以外的其他双拼方案
- LLM 润色和云服务
- Squirrel 分叉、公证和正式发布

## 许可证

本仓库自有代码采用 MIT License；标有 SPDX 例外声明的文件采用其标注许可证。Squirrel、WhisperKit 及将来引入的词典数据分别遵循各自许可证；当前人工翻译词条未复制 CC-CEDICT 数据集。RoType 仅在用户本机部署时引用 Squirrel 自带的 Luna Pinyin，不在仓库或 App 中重新分发该词库。详情见 `THIRD_PARTY_NOTICES.md`，构建产物会携带当前 WhisperKit 依赖的原始许可证与 notices。
