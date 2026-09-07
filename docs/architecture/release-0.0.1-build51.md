# 0.0.1 Build 51 — R 图标宽度

## 根因与修复

在用户菜单截图中，ABC 为 44×32 px，Build 50 的 R 为 28×32 px。此前只检查 PDF 自身尺寸，没覆盖系统对 NSImage 的二次绘制，这是错误方向。

在独立诊断进程中检查当前 macOS 的 TextInputMenuUI 图标绘制逻辑：`InputSource.newIcon` 将原图交给 `createAlignedImage`，使用 22 pt 的输出画布。原图宽度介于 16 和 22 pt、且高度不超过 16 pt 时，按原尺寸居中；宽度超过 22 pt 时，则压入 16×16 pt 的矩形。

旧 PDF 的画布是 24×16 pt，内部图形为 22×16 pt，因此触发缩窄分支。扩大画布会让实际图标更窄，不能解决问题。

Build 51 改为：

- PDF 画布 22×16 pt，底板占满 22×16 pt；字体和高度不变。
- 图形中心由 x=12 调整到 x=11，不拉伸字母。
- 保留三个显式图片配置，资源改名为 `rotypeABC22Template.pdf`。
- 不再使用 Build 49 的 labels-only 方案，不添加新的 padding 元数据或私有运行时调用。

## 在改动用户安装前完成的验证

`Tests/MenuIcon/SystemRendererProbe.m` 是独立的诊断可执行文件，动态调用当前系统的实际图像变换函数。它不注册、启用或选择输入源，不操作 TextInputMenuAgent，不连接真实麦克风，也不链接进产品。

同一函数对两版图片的输出：

```text
旧 PDF 24×16 pt → 系统画布 22×16 pt → 可见 28×32 px：FAIL
新 PDF 22×16 pt → 系统画布 22×16 pt → 可见 44×32 px：PASS
```

旧输出与用户菜单实测一致。该测试已加入 `scripts/test-user-experience.sh`，不能再只用 PDF 几何测试宣布菜单修复。诊断符号在其他系统不可用时明确 SKIP，不作该系统绘制已通过的声明。

`Tests/MenuIcon/test-menu-icon.swift` 同时约束画布必须为 22×16 pt，防止以后再扩大到 24 pt。

## 构建与交付状态

- `scripts/test.sh` 通过，71 项 Swift Testing 测试通过，实际系统图像变换测试通过。
- 安装包构建与 Developer ID 签名完成。
- 公证最初因 `RoType-notary` 无法读取而中断。2026-09-07 重查已有凭据成功，未重建凭据或降低验证要求。公证 Accepted：`1322a22c-6cb6-477b-b7da-930486d20025`，stapling 与 Gatekeeper 均通过。
- 已经用户的系统管理员授权完成安装，宿主和 helper 均确认为 Build 51，已安装 Bundle 的 deep/strict 签名校验通过。
- 管理员安装器初次从 Downloads 读取包时报告路径无效；将同一个已验证公证的包复制到私有临时目录后安装成功。未调整系统目录保护或 TCC。
- 注册信息确认使用 `rotypeABC22Template.pdf`，NSImage 大小为 22×16 pt。菜单进程仍曾缓存旧 R；只刷新当前用户的 TextInputMenuAgent 后，实际菜单截图测得 **ABC 44×32 px、R 44×32 px**。
- 实机验收日志：`menu-accepted.log`；截图：`installed-menu.png`，同时复制到 `~/Downloads/洛克-build51-菜单图标实测.png`。

日志：`/tmp/rotype-release-0.0.1-b51/`，包含 `icon-red.log`、`icon-green.log`、`tests.log`、`build.log` 和公证错误记录。
私有框架探索脚本、反汇编和临时图均只在 `/tmp/`；产品不使用这些接口。官网仍提供 Build 48 的原安装包与对应源码。

交付安装包：`~/Downloads/洛克输入法-0.0.1-build51-macOS-arm64.pkg`，附 SHA-256。计时对齐、侧栏焦点样式与官网图标修改继续保留。
