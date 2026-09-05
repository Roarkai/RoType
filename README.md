# 洛克输入法（RoType）

洛克输入法是一款面向 macOS 的双向双语键盘输入法。Rime 负责中文与英文候选，后台服务使用 Apple Translation 异步生成动态翻译候选。

本仓库同时维护基于 Squirrel 1.1.2 的 GPL v3 前端修改。设置入口直接出现在输入法菜单中；按需启动的设置 helper 与无 UI 翻译 worker 均内嵌在输入法 Bundle，不在 `/Applications` 安装独立 App，也不显示 Dock 图标。

## 当前功能

- 中文拼音先产生正常 Rime 候选；Apple Translation 跟随当前高亮项，译文显示在独立操作栏。
- 英文单词可直接翻译；英文短语使用单引号代替 composition 内的空格，例如 `what'are'you'doing`。
- 动态结果严格匹配当前输入、选中候选和分段范围；切换候选或翻页后不会提交旧译文。
- Rime Lua 通过 session property 把候选语义交给 Squirrel；输入法通过带 generation 的 Mach XPC 请求后台翻译，不扫描请求目录。
- 通过 Squirrel 自带的 Luna Pinyin 词库提供完整全拼中文候选。
- 提供独立的“洛克输入法（小鹤双拼）”方案。
- 动态翻译不可用时，在同一译文栏使用人工校准静态词条；按当前候选原文匹配，不按拼音猜词，也不拼接未知句子。
- 每页最多 5 个候选；译文不占候选编号，点击或按 Tab 直接上屏，无需再按回车。
- 首次配置向导检查输入法是否真实接管键盘，并准备简体中文与英文语言包。

产品不再包含语音功能、Python/MLX 运行时或模型下载入口。升级时停止并移除由 RoType 签名的旧语音 App，保留已下载的模型和历史数据。输入法、设置 helper 和翻译 worker 不申请麦克风或全局输入监控权限。

任意短语的动态翻译当前使用 macOS 26 的无界面 `TranslationSession`；更早系统走静态双语热词分支，不发送动态翻译请求。词条未命中时明确提示不可用。密码框和 macOS Secure Input 不在支持范围内。

本轮优化尚未发布安装包；静态匹配与提交逻辑已做隔离验证，macOS 14/15 实机与跨应用输入验收仍待完成。进度见 [整体优化计划](docs/architecture/optimization-plan.md)。

## 环境

- macOS 14+
- 动态 Apple Translation 需要 macOS 26+
- Apple Silicon 优先
- Xcode 26+（需要 macOS 26 Translation SDK）
- Squirrel，正式发行包包含 librime-lua 和 Luna Pinyin 词库

## 验证 Rime 方案

1. 安装洛克输入法。
2. 从洛克输入法菜单选择“重新部署”。
3. 选择“洛克输入法（全拼）”或“洛克输入法（小鹤双拼）”。
4. 打开洛克输入法设置，按向导准备中英翻译语言包。
5. 全拼输入 `nizaiganma`，等待英文翻译候选自动出现；输入 `computer` 或 `what'are'you'doing` 验证英文到中文。

RoType 中文候选使用鼠须管随包提供的完整朙月拼音词库和八股文语言模型，并保留用户词频学习。全拼与小鹤双拼默认启用常用模糊音；全拼另外支持简拼、拼写纠错和常见按键纠错。

RoType 的方案、Lua 模块和预编译词典随签名输入法 Bundle 安装。每个 macOS 用户在首次启动输入法时获得独立的 `~/Library/Rime` 学习数据；升级自旧版本时，安装在用户目录中的旧 RoType factory 文件会先备份到 `~/Library/Rime/rotype-backups/`，再改用 Bundle 内版本。用户自己的 `default.custom.yaml` 不会删除。

## 构建设置与翻译服务

```sh
./scripts/build-app.sh
open "dist/洛克输入法设置.app" --args --show-settings
```

首次从输入法菜单打开设置时会显示配置向导，验证输入源并准备 Apple 中英翻译语言包。设置 helper 只在用户打开窗口时运行；独立的 `im.roarkai.inputmethod.Luoke.translation` Mach service 按需处理请求。每个请求带有随机 Rime session token 和单调 generation，旧任务会被取消，连接中断后会自动重建。worker 按签名身份区分主输入法和设置 helper：只有主输入法可以翻译，只有设置 helper 可以查询由主输入法记录的真实按键 generation；分布式通知只用于触发重新查询，不能直接提供验证结果。Secure Input 启用时不会请求翻译或写入响应缓存。翻译响应由当前 `SquirrelInputController` 校验会话快照并更新独立翻译栏，不重排 Rime 候选，不写响应文件或模拟系统按键。

安装器不把注销设为正常切换依赖。它会即时执行并验证公开的 `register -> enable -> select`；若当前登录会话没有形成可验证状态，系统 payload 仍保留，安装器会写入 `input-source-setup-required` 并打开设置向导，由用户完成菜单选择和真实键盘输入验证。系统级 LaunchAgent 会为以后登录的用户自动加载，升级时也会更新所有当前活跃 GUI session，但不会替其他用户强制切换输入源。

## 构建发布安装包

先使用 Squirrel 官方锁定的通用二进制依赖构建 Release 版本，再生成统一安装包：

```sh
SQUIRREL_BUNDLED_RECIPES=:preset bash Squirrel/action-install.sh
make -C Squirrel release
./scripts/build-installer.sh
```

构建脚本默认使用团队 `DF7J2VBQD8` 的 Developer ID Application / Installer 证书。可通过 `ROTYPE_CODESIGN_IDENTITY` 和 `ROTYPE_INSTALLER_IDENTITY` 覆盖默认身份。

首次公证前保存 Apple 公证凭据，然后提交并 stapling：

```sh
xcrun notarytool store-credentials "RoType-notary" \
  --apple-id "nitthiko@gmail.com" \
  --team-id "DF7J2VBQD8"
./scripts/notarize-installer.sh
```

## 测试

```sh
./scripts/test.sh
```

Lua 测试验证候选排序、无旧响应文件读取和兼容入口无副作用；Swift 测试验证候选合约、静态兜底、过期结果隔离、取消/重试与输入源验收逻辑。开发安装测试验证模块复制及用户配置保留。测试通过不代表 InputMethodKit 和系统语言包已完成真实验收。

旧文件/F18/编号翻译路径已退出活动链路。自定义方案的支持范围见 [旧翻译链路清退与兼容说明](docs/architecture/legacy-translation-retirement.md)。

签名 XPC 集成测试使用随机服务名、临时 Release 构建和严格签名鉴权，不再替换已安装的 LaunchAgent：

```bash
zsh scripts/test-xpc-isolation.sh
```

此检查需要 Developer ID Application 证书和 GUI 登录会话；覆盖正常结束与启动后故意失败的清理。若生产服务已安装，会建立只读状态连接，验证连接不中断、进程不被替换。该连接可能按需唤醒空闲服务，不提交翻译原文。打包脚本已接入此检查。夹具使用同一服务实现，但不是最终安装包中的二进制，不能替代安装后的真实输入验收。

若有包含当前 RoType 工厂数据的解包输入法 App 或隔离夹具，还可以运行真实 Rime 部署测试（原版上游 App 和旧发布包不适用）：

```sh
ROTYPE_SQUIRREL_APP="/path/to/current-fixture.app" ./scripts/test-rime-deploy.sh
```

加 `ROTYPE_RIME_BENCHMARK=1` 可运行固定输入的底层逐键基准。候选流已改为保持原排序的惰性处理；测量范围、对照结果与最坏情况见 [性能记录](docs/architecture/candidate-performance.md)。

## 当前非目标

- 语音录音、ASR、语音模型管理
- macOS 14-15 的 CTranslate2 + OPUS-MT 本地翻译兜底
- 小鹤以外的其他双拼方案
- LLM 润色和云端翻译服务

## 许可证

本仓库自有代码采用 MIT License；标有 SPDX 例外声明的文件采用其标注许可证。Squirrel 及词典数据遵循各自许可证。当前人工翻译词条未复制 CC-CEDICT 数据集。详情见 `THIRD_PARTY_NOTICES.md`。
