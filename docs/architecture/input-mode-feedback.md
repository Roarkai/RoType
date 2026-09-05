# Shift 切换与中英文状态提示

## 已复现的问题

**后续修正**：以下临时英文/键码修正并未独立解决现场问题。最终发现内部 F19 查询取消 Shift 手势，详见 [开源输入法对照与现场验证](../research/2026-09-05-open-source-ime-shift-handling.md)。

0.0.1 继承的默认配置是左 Shift `inline_ascii`、右 Shift `commit_text`。前者在有拼音组合时只进入临时英文，提交后通过 Rime 的 OnContextUpdate 回到中文，不符合持续切换的预期。

真实 Rime 回归在旧包数据上报错：`FAIL: Shift English mode reset after submission: rotype 65505`（退出码 192）。这证明了一种真实的失效表现，不代表已经排除了所有 IMK 修饰键事件问题。

## 修正

- 全拼和小鹤方案显式采用左右 Shift `commit_code`。
- 在有未上屏输入时，Rime 保留已确认前缀并提交剩余原始输入，再进入持续英文；不由前端手动重组文本。
- 再轻按 Shift 回中文；Shift+字母不误切换。
- 仍遵守 librime 的轻按时限（500ms）。未修改上游硬编码时间，不声称长按后松开一定切换。
- 输入 controller 激活时同步当前修饰键和应用选项，避免提示使用尚未应用的默认模式。

真实 Rime 全拼/小鹤、左右 Shift、提交后模式保持、再次切回及 Shift+字母回归通过；原整句/分段/分页测试继续通过。

## 状态提示

新增 `RoTypeInputModePanel`：切入洛克或实际 ascii_mode 改变时，在有效光标位置附近显示约 1.1 秒；中文为米白圆形“中”，英文为橙色圆形“EN”。输入普通按键立即隐藏，离开输入上下文也隐藏。不抢焦点、不接收鼠标、不占候选编号；无有效光标矩形则不猜测位置。

模块保留可选 PNG 资源入口 rotypeModeZh / rotypeModeEn，当前使用原生绘制。用户指定的 gpt-image-2 已尝试通过 OpenAI images/edits 调用，但认证返回 401，因此没有生成模型图片，不能把原生预览标为 GPT 产物。

原生面板测试验证不可激活、边缘定位、旧计时器不能隐藏新提示、自动消失和无效矩形处理。预览位于 `/tmp/rotype-mode-preview/{zh-native,en-native}.png`。

## 本机与交付状态

- 全量常规测试（含 32 个 Swift 测试）及输入法 Release 构建通过。
- 当前用户原本不存在两份方案 custom 文件；已新建 `~/Library/Rime/rotype.custom.yaml` 与 `rotype_flypy.custom.yaml`，只修正 switch_key，不改词库和学习数据。隔离部署验证了这两份补丁在已安装 0.0.1 工厂数据上编译为 commit_code。
- 后续已安装签名、公证的 build 35，并应用 F19 前置查询的本机临时补丁、重新部署。左 Shift 实际 IMK 中→英→中已验证；临时补丁清理要求见上文后续研究。
- 原生圆形提示已随 build 35 安装，但用户报告的蓝色 R 不属于该绘制内容，来源与提示体验仍待验收。build 35 安装包本身未包含 F19 修正，不应作为完整 Shift 修复包再次交付。
