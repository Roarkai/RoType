# 0.0.1 / build 36

本次收录 main 工作区的安装引导、Shift 和输入模式提示改动。

- 首次设置引导用户在 macOS 原生键盘设置中添加输入源；不再自动 enable/select 冒充完成原生菜单登记。正常升级保留设置进度。
- 左右 Shift 使用持续英文策略；修饰键缺失物理键码时按实际变化的修饰键识别。
- 内部 F19 快照在 ascii_composer 前被专用只读处理器消费，避免打断 Shift 按下/松开的手势。F20 提交保留原处理链。
- 原生“中 / EN”光标提示来自程序绘制，不是 gpt-image-2 图片。指定图片接口认证失败，未生成或打包模型图片。

相关验证：`scripts/test.sh`、`scripts/test-rime-deploy.sh`。Rime 回归包含真实控制器顺序 Shift→F19→release，不再只测试连续按下/松开。实际 UI 验收及限制见 [开源输入法对照](../research/2026-09-05-open-source-ime-shift-handling.md)。签名、公证和包体校验在产物生成后单独执行，构建成功不代替现场验收。

## 本机临时设置不属于发行默认值

- 此前 build 35 的 `~/Library/Rime/rotype*.custom.yaml` 含临时 `engine/processors/@before 0` 插入。升级到 build 36 后可移除该单条插入，避免快照处理器重复；不应删除整份用户 custom 文件。重复快照处理器的第一个会消费 F19，其余按键均透传，但无需保留重复。
- 用户授权关闭了本机系统光标输入源提示（`TSMLanguageIndicatorEnabled=false`）。备份在 `~/RoType-Backups/input-indicator-20260905-194907/`；安装器不改其他用户的全局提示偏好。
- 本次只产出发行包，不自动再次安装或覆盖用户正在运行的输入环境。
