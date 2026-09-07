# 0.0.1 Build 50 — 恢复 R 图标

日期：2026-09-06。

Build 49 的 labels-only 图标方案在实机失败：旧菜单进程显示缓存的 R；刷新后显示通用输入法图标。Build 50 恢复 Build 48 的三个显式 R PDF 图片键，不再依赖单独的 TISIconLabels。**这是回退修复，不是 ABC 宽度修复。** R 横向仍比 ABC 窄，该问题尚未解决，后续不能再用用户当前输入源做未经验证的方案试验。

保留 Build 49 的修改：

- 录音计时下移 2 pt，可见数字与波形中心对齐。
- 设置侧栏禁用蓝色 focus effect，保留键盘操作和中性焦点反馈。
- 侧栏底部仅显示指向 type.roarkist.com 的官网图标。

验证：`scripts/test.sh` 通过，71 项 Swift Testing 测试通过，含五个计时文本的实际像素对齐测试。签名、公证、stapling、Gatekeeper 通过。

公证 ID：`fe9a423e-9177-4276-9f62-ddc336ec2983`。
日志：`/tmp/rotype-release-0.0.1-b50/`。
交付：`~/Downloads/洛克输入法-0.0.1-build50-macOS-arm64.pkg`，安装器已打开。
官网仍提供 Build 48，版本化包与源码未被替换。
