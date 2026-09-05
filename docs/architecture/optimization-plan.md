# RoType 整体优化计划

状态：用户已确认四个测试边界。步骤 1–10 的首轮实现与隔离验证完成；其余步骤待实施。未发布新安装包。

## Problem Statement

针对 0.2.31 当前工作区的整体 review，处理五项行为问题与五项架构优化。当前全量测试通过，但不足以证明候选语义、语音卸载和真实 IMK 交互正确。

已确认的证据：

- 真实翻译服务收到输入码 `can`、高亮中文 `餐`，却按英→中翻译 `can`，返回“装罐量”。
- 旧语音启动脚本没有 `stop` 命令协议；安装器传入该参数不能可靠停止服务。实施中进一步确认原 `codesign -R` 缺少内联 requirement 的 `=` 前缀，清理分支因此被跳过。review 时还发现旧开发构建的语音服务监听本机 8991 端口。端口存在不等于正在录音。
- 同一候选失败后不会重新请求；翻译后端将所有重试失败统一报告为语言包缺失。
- 新展示模式抑制静态翻译，低于 macOS 26 又没有动态后端，存在兼容缺口；尚无低版本实机验收。
- 打包测试替换真实翻译 LaunchAgent；协议字段分散、旧链路仍存、过滤器预先消费整个候选流；部分测试只检查代码文本。

## Solution

保留每页五项、无语言/范围标签、Tab 直接选用译文、不恢复语音的产品约束。分阶段解决正确性、恢复能力、兼容、测试隔离和性能。先验证每个行为问题，再进行可回退的结构精简。

### 覆盖矩阵

| Review 项目 | 对应步骤 |
| --- | --- |
| 翻译对象与方向错误 | 1、5 |
| 语音后台退出不可靠 | 2、3 |
| 失败后不能重试 | 6 |
| 错误分类与取消处理 | 7 |
| 低版本静态兜底 | 8 |
| 测试影响真实服务 | 4 |
| 统一快照协议 | 5 |
| 删除旧翻译链路 | 9 |
| 惰性候选与性能 | 10、11 |
| 真实交互测试覆盖 | 12、13 |

## Commits

以下是小步实施单元，不代表自动提交 Git。保留当前工作区，不重置、不覆盖既有改动。每一步保持可运行，逐条完成测试—实现—验证，不提前批量写完所有测试。

1. **Fix translation source selection.** Add one regression through the translation request/reply boundary for `can` with selected `餐`, then make selected-source semantics authoritative. Preserve legitimate English-candidate translation and segmented composition. Record the temporary compatibility behavior before changing the wire protocol.
2. **Verify the legacy voice retirement contract.** Reproduce shutdown against isolated legacy fixtures. Do not execute a presumed `stop` command on a script that does not implement it. Cover running and stopped services without starting a real voice runtime.
3. **Implement verified voice retirement.** Identify owned processes by user and exact executable/application identity, request termination, and verify exit before declaring success. Treat packaged installations separately from old developer builds. Never kill an arbitrary listener on port 8991. Preserve models and history; report incomplete cleanup instead of silently succeeding.
4. **Isolate translation integration tests.** Introduce a test-only service endpoint/configuration that cannot redirect production clients. Stop replacing the installed LaunchAgent during builds. Preserve signing requirements and role authorization. Verify both success and failure cleanup leave the production service unchanged. Do not run the current disruptive integration harness before this step is complete.
5. **Version and centralize the candidate translation contract.** Make source, direction, scope, identity and request freshness explicit. Validate at the Swift/Lua/XPC boundaries. Define mixed-version behavior for upgrades and reject incompatible requests safely. Remove backend guessing for explicit candidate requests; preserve any transitional API only with a documented removal condition.
6. **Add bounded retry behavior.** Permit retry of a failed current candidate without requiring selection changes. Distinguish ready, loading and retryable failure; Tab commits only ready text and can initiate an explicit retry after failure. Superseded results never become eligible for submission. Bound automatic retries and prevent duplicate in-flight work.
7. **Preserve cancellation and error meaning.** Propagate cancellation without recreating sessions or retrying. Classify missing language packs separately from transient service failures and unsupported platforms. Reset sessions only when justified by a recoverable error. Validate final error messages through the translation boundary.
8. **Restore static fallback in the new presentation.** Present matching bundled static translations in the independent row when dynamic translation is unavailable. Preserve five-item paging and segment-aware commit semantics. Do not silently return to ninth-candidate insertion. If no static match exists, show an honest unavailable state. Track low-version hardware validation separately from injected capability tests.
9. **Remove obsolete translation machinery.** Inventory legacy schemas, response-file writers/readers and refresh events. Define whether user-customized schemas still need a compatibility path before removing it. Delete unreachable paths and their implementation-specific checks only after replacement behavior is covered. Never overwrite customized user schemas to simplify migration.
10. **Measure and make panel-mode filtering lazy.** Establish repeatable candidate latency/allocation baselines. Stream candidates in the panel path rather than materializing the entire input stream where semantics allow. Verify order, candidate limits, simplified filtering and segmented selection remain unchanged.
11. **Add bounded in-memory result reuse.** Only add caching where measurements show repeated requests. Key results by effective source, direction and backend semantics; bind reused text to the current ticket, never to an old commit identity. Bound entries/bytes/lifetime, exclude failures and cancellations, and avoid persistent plaintext input storage. Document privacy and invalidation behavior.
12. **Exercise actual user actions.** Add controller/IMK acceptance for Tab, mouse selection and click, page changes, Escape, segmented input, focus changes and out-of-order responses. Keep pure session tests, but do not treat them as proof that a real key or click was handled. Use disposable documents/windows, never overwrite user content.
13. **Validate release and upgrade behavior.** Run unit, real Rime, isolated signed XPC, upgrade and installed-UI checks. Verify light/dark display, long translations, screen edges, multiple representative apps and voice-process retirement. Sign and notarize only after the relevant gates pass. Update documentation with actual results and remaining platform gaps.

## Decision Document

- 翻译原文由当前候选语义决定；拼音碰巧是英语单词不能推翻用户选择。
- 请求模型明确区分输入码、翻译原文、方向、范围、候选身份与时效。共享语义不意味着跨语言强行共享实现。
- 新翻译区是唯一目标展示路径；静态兜底也进入该区域，避免维护第二套编号与提交规则。
- 整句与分段提交继续分开处理。后续输入、焦点变化和取消必须使旧提交资格失效。
- 失败重试不复用旧结果，不无限自动重试，不把取消伪装成缺语言包。
- 测试隔离优先于再次运行签名 XPC 集成测试。产品客户端不接受任意外部指定的服务端点。
- 语音移除包含进程生命周期，而不仅是删除文件。正式安装与开发遗留分别处理；无法确认身份时不终止进程，保留诊断信息。
- macOS 26 以下保留静态翻译能力，不新增本地大模型后端。没有匹配时明确不可用。
- 性能工作以测量为依据；缓存仅在内存、有界，不落盘记录输入正文。
- 不自动推送、创建远程 issue 或提交当前混合工作区；阶段记录保存在仓库。

## Testing Decisions

用户已确认的测试边界：

1. **翻译请求/回复**：有效原文与方向、取消、错误类型、协议兼容、授权；后端替身只用于可控的延迟和失败，不替代真实签名 XPC 验证。
2. **真实 Rime 输入/提交**：高亮、分页、原文快照、整句与分段提交、静态兜底；检查实际候选与提交，不依赖源码字符串。
3. **安装/卸载外部行为**：隔离进程与 LaunchAgent fixture 的启动、停止、身份拒绝和退出结果；不替换当前用户的生产服务。
4. **实际 IMK 用户交互**：真实 Tab、点击、焦点切换及应用中的文本结果；纯状态机测试只能作辅助证据。

现有候选 session、Rime 集成、翻译 coordinator、签名 XPC 和升级退出测试作为基础。针对一条可观察行为先复现失败，再实现最小修复。未具备实机的平台与应用明确标记“未验证”。

## Out of Scope

- 恢复语音、实时听写或新增语音模型。
- 新增云翻译、低版本动态模型下载器。
- 删除用户模型、历史、词库或定制配置。
- 清空输入源注册、强制删除 ABC、重置系统偏好或降低签名校验。
- 重新设计整套视觉风格、强行拆分所有大文件、审计第三方 librime 全部内部实现。

## Further Notes

### 首轮实施记录

- 步骤 1：通过请求/回复边界先复现 `can / 餐`，再修复原文选择；随后复现 `hel / hello`，修复英文补全原文。客户端同步接受完整候选结果、拒绝输入码结果。两个请求回归和客户端结果验证均经历失败到通过。
- 过渡限制：XPC 签名未改变；当前方向仍暂按候选是否为 ASCII 分类，不能宣称 Unicode 英文或混合语言已完全解决。步骤 5 仍需显式语言语义与版本化协议。旧客户端可能拒绝原文与输入码不同的英文补全结果，而不是错误提交；升级验收仍待做。
- 步骤 2–3：新增安装器专用原生退出工具，不执行旧启动脚本、不信任 pidfile、不按端口或名称模糊杀进程。严格校验旧应用与嵌套代码，核对程序路径、用户与启动时间，并确认 Python 的实际参数指向随包 server。仅发 SIGTERM，超时保留应用并阻止安装。
- 安装器在语音退出通过后才卸载输入会话服务，避免语音退出失败导致现有翻译服务先被停掉。签名无法确认的应用会保留并明确告警。
- 签名隔离夹具验证：两个目标进程退出、相似参数的无关进程存活、旧启动脚本从未执行；忽略 SIGTERM 的进程阻止移除；资源被篡改的应用与进程均保留。测试启动状态通过 ready 文件同步，避免把进程尚未安装信号处理器误判成退出策略正确。
- 已用新工具核验并停止现场旧开发构建的一个语音服务进程，随后未发现语音服务进程或 8991 监听。没有删除模型、历史、系统应用或重置输入源。
- 全量常规测试通过，Swift 测试增至 13 项；语音签名集成测试单独通过，并已接入打包门禁。尚未运行会替换生产服务的旧 XPC 集成脚本，也尚未打包/安装本轮改动。
### 第二轮实施记录：XPC 测试隔离

- 步骤 4 已完成：每次创建随机 UUID 服务名、临时 Release 构建和独立 LaunchAgent；测试与清理只操作自己的标签。移除旧测试对生产 LaunchAgent 的 bootout/bootstrap/恢复逻辑。
- 服务主体与鉴权实现不变。只有独立 scratch 构建启用的测试编译条件接受 UUID 测试端点；正式入口仍固定生产服务名，不接受环境变量或参数重定向。打包增加误装测试夹具的静态检查。
- 先在独立标签复现原入口无法完成握手的失败，再启用测试入口使其通过。授权输入法访问、ad-hoc 调用拒绝、设置角色仅允许状态读取、空闲退出与重新唤醒均通过。
- 不再把超时当成鉴权拒绝；先完成正向握手，再检查拒绝路径。回复还验证错误域与具体错误码，避免把其他服务错误误当成鉴权通过。
- 隔离验收分别运行正常用例和工作进程完成握手后故意退出 42 的失败用例；两次均确认临时标签消失。生产服务只读见证连接全程保持，PID 67407 未变。见证连接可按需唤醒原本空闲的服务，不发送输入文本或修改用户数据。
- 无生产服务的环境不假装完成生产连接验收，只验证临时清理及没有意外创建生产标签。保留 GUI 会话和 Developer ID 证书要求，不允许无签名绕过。
- 正式 Release 服务编译通过，确认不包含测试端点前缀。全量常规测试通过。测试夹具虽使用相同主体实现，仍不等于最终签名安装包实测；本轮没有构建安装包或改变已安装版本。
### 第三轮实施记录：版本化候选合约

- 步骤 5 首轮完成，详见 [候选翻译协议 v2](candidate-translation-contract.md)。共享原文、方向、范围、候选身份、版本及长度校验，新增字符串字典载荷的 XPC selector，保留 v1 selector。
- 输入法发送完整输入码与实际候选原文，不再为分段请求替换 rawInput。服务按已校验的显式方向翻译；原生客户端还校验返回代次、方向与原文。
- 重音英文、组合音标、弯引号、中英混合及扩展区汉字通过请求回归。策略为 Han 优先、Latin 按英语映射，不宣称实现通用语言检测。
- 未知版本与非法字段在调度前拒绝，不消耗代次或取消合法请求。新接口保留签名与角色限制，未增加降级到猜测模式的通道。
- Rime 属性读取新增 NUL 终止检查，截断时拒绝快照，避免将满缓冲区当成无界 C 字符串读取。
- Swift 常规测试增至 16 项（含参数化用例）；候选 session、独立签名 XPC、输入法 Release 构建和真实 Rime 分页/分段提交测试通过。构建后仅取消构建副本的 LaunchServices 注册，不动已安装输入源。
- v1/v2 同服务调用已验证；真实旧二进制混合升级与跨应用输入仍待最终安装验收。本轮不打包、不更改已安装版本。
### 第四轮实施记录：恢复、取消与错误分类

- 步骤 6–7 首轮完成。可恢复失败后，Tab 与点击走同一个操作入口，创建新代次重试当前快照；成功结果仍需另一次用户操作提交，重试本身不自动上屏。
- 观察相同快照/重绘不会自动重试；加载中禁止重复请求；重试期间忽略 Tab 的重复 keyDown。旧代次和同代次的重复终态回复不能覆盖当前状态。切换到无效候选也会取消之前的请求。
- 翻译区显示具体错误，可重试时显示提示并启用按钮；缺语言包、系统不支持、协议/权限错误等不启用无意义的立即重试。
- 新增共享错误码与恢复策略；超时、服务不可用、缺语言包、取消、语言不支持、协议和非法响应分别处理。不再把任意系统错误报成语言包缺失，也不把客户端超时编码成非法请求。
- 只有 Apple 明确返回 internalError 才在 250ms 退避后重建会话并自动重试一次；第二次失败直接保留错误类别。未知错误不自动重试。取消不重建会话、不重试，并优先于迟到的语言包错误。
- Apple SDK 会话作为系统边界替身，测试覆盖调用前取消、系统调用挂起时取消、退避时取消、一次恢复、持续故障和错误沿请求/回复边界保真。coordinator 在所有终态清理任务，并用代次保护新任务不被旧任务清理。
- 全量常规测试通过，Swift 测试增至 25 项（含参数化用例）；候选状态/响应校验与输入法 Release 构建通过。独立签名 XPC 的权限和清理回归通过，生产见证连接及 PID 79898 保持。
- 当前是状态机、系统边界、签名接口与构建证据；Tab/点击跨应用实机验收仍在最终安装阶段，不能将状态测试称作实际按键验收。未发布新安装包。
### 第五轮实施记录：静态翻译兜底

- 步骤 8 首轮完成。共享候选合约提供 10 组人工校准词条与显式英文别名，按实际原文匹配，不按拼音或模糊拆词推断。
- macOS 26 以下在控制器中走本地处理，不发送动态翻译请求；macOS 26 动态请求缺包、超时或服务不可用时，也可使用精确匹配的静态结果。
- 保留现有译文栏、Tab/点击提交、代次与快照校验。取消、权限、协议及非法响应错误不会被静态结果掩盖；静态结果完成后不接受迟到的动态覆盖。
- 没有词条时保留错误与重试策略；低版本明确显示“无匹配的静态译文”。同拼音不同候选、未知整句不得复用/拼接词条。
- 状态回归经历失败到通过，覆盖中英双向、10 组词条、双拼、分段、无匹配、旧失败与迟到结果。真实 Rime 验证整句 hello 提交、英文词段替换并保留后续 shu 输入；该隔离词库中全拼和双拼各扫描 159 页，所有页不超过 5 项且没有静态 hello 编号项。
- 测试夹具修正了对 Rime Highlight 返回值的误解：已高亮同一项时 false 表示未变化，不能当成失败。测试改为检查实际快照；没有为使测试通过而改动产品高亮逻辑。
- 全量常规测试、独立签名 XPC 和 Release 构建通过；生产见证连接与 PID 92752 保持。SDK 能力分支尚未在 macOS 14/15 硬件执行，不能把模拟不可用状态或 Rime 测试称为完整低版本 IMK 验收。
- 旧 Lua 路径及兼容词表暂留，未覆盖用户定制配置。README 移除无依据的“零延迟”表述，并修正构建所需 Xcode SDK 版本。
### 第六轮实施记录：旧链路清退

- 步骤 9 完成。两个官方方案移除旧 translator、F18 processor 与编号译文提交 processor，使用纯排序 `rotype_candidate_filter`；翻译只走原生会话、XPC/静态兜底和 F20。
- 删除原生响应文件存储类及工程引用、旧 Lua 请求属性与文件读取、重复静态词表；保留通用键盘 F18 映射和 XPC v1 selector，它们不是这次清退的对象。
- 四个旧 Lua 名字仅作加载兼容：filter 转交纯排序，其余无输出或 kNoop。自定义方案普通输入可继续，旧编号译文不再提供；新译文栏仍要求 candidate_session。支持范围详见 [兼容说明](legacy-translation-retirement.md)，没有改写用户私有 Lua/配置或删除历史缓存。
- 新 Lua 回归先复现旧链路读取响应文件，再验证零文件访问、零旧属性发布、候选顺序与遗留译文过滤。另修复非 ASCII echo 把自己当前置候选而重复输出的问题。
- 真实 Rime 回归改为通过 F19/F20 验证已确认前缀的整句翻译，不再创建响应文件。使用新工厂数据和重新编译的方案，整句/分段/分页测试及旧自定义方案的加载、F18 无操作和普通中文提交均通过。三种方案测试各扫描 159 页，没有编号 hello。
- 修复开发 install-rime 脚本漏复制新候选模块的问题，并停止创建旧 bridge 目录。隔离安装回归验证备份与用户配置/无关 Lua 保留。
- 全量常规测试、签名 XPC 和输入法 Release 构建通过；生产见证连接及 PID 5394 保持。旧测试与存储源码移到仓库外临时备份，位置记录于 `/tmp/rotype-retired-chain-latest`。
- 本步保留既有 eager 排序模型，避免清理与性能改造同时改变行为。

### 第七轮实施记录：惰性候选流

- 步骤 10 完成。先冻结步骤 9 排序基线，再建立合成拉取与真实 Rime 逐键基准，执行旧→新→旧对照。详见 [性能记录](candidate-performance.md)。
- 首屏不再为寻找远处 echo 而完整扫描：10,000 项合成流中，中文首项场景前 5 次输出只读 5 项；echo 首项场景读 6 项。相应 Lua 堆增量由约 1.7 MiB 降至约 2.5 KiB。纯英文歧义流仍需全量扫描，不宣称普遍 O(1)。
- 真实 Rime 基准中，nihao 样本的逐键 P95 从 18.837ms 降至 0.184ms；切回旧实现复测为 16.998ms。数据不包含 UI、XPC 与 Apple 翻译耗时，不代替实机体验验收。
- 完整顺序通过 600 组固定种子对照，以及大候选流、重复实例、无 echo 等边界回归；旧排序实现仅保留为测试 oracle，不进入产品。
- 真实 Lua 绑定发现并纠正了初版对迭代器 ABI 的假设；现在转交 state/control，补入回归。真实 Rime 整句/分段/全部分页与兼容方案均通过。
- 全量常规测试与签名 XPC 隔离回归通过，生产见证连接与 PID 17616 保持。本步未改原生 Swift 实现、未打包或安装。
- 原定下一步为步骤 11（有界内存复用）；按用户新增优先级，先收尾首次配置和重复安装体验，暂不实现缓存。

### 插入阶段：首次配置与升级体验

- 实现配置进度持久化、旧完成标记沿用、关闭向导后的暂缓选择、语言包可选准备及已有语言包只读探测。历史配置与当前输入源可用性、实时 controller 验证分开。
- 首次安装成功后也打开设置；正常升级不重复打开已完成/已暂缓向导。预安装不主动禁用输入源，已配置用户安装收尾不强制启用、选择输入法。错误只引导检查，不清空已有配置。
- 全量常规检查、32 个 Swift 测试、安装状态组合回归、设置助手 Release 构建和签名 XPC 隔离回归通过；生产见证连接及 PID 36350 保持。
- 真实 Rime 回归通过。词库只建立 16 项目标文本可见率基线，未加词、换库或改用户词频。
- 实现细节与实际安装验收清单见 [安装配置体验](installation-setup-experience.md)；词库观察与优化边界见 [词库基线](vocabulary-baseline.md)。
- 尚未打包、安装或完成真实窗口/升级验收。按用户要求收住范围，先交付本阶段验证结果，不继续扩展缓存或词库。
- 测试全部通过不是跨应用验收完成。安装、进程退出、协议测试与真实输入分别记录。
- 每阶段完成后更新本文件的进度、证据和新增风险；发现兼容性决策冲突时暂停该项，不扩大改动范围。
