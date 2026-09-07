# 0.0.1 Build 49

日期：2026-09-06。已签名、公证并打开 Downloads 中的安装包；打开安装器不代表安装已完成。

## 改动

- 录音计时：原 11 pt NSTextField 的可见数字中心相对波形偏上 4 个 Retina 像素。保留 188×36 pt HUD，把计时字段下移 2 pt；没有改录音、识别或提交链路。
- 设置侧栏：禁用系统蓝色 focus effect，保留键盘焦点与中性背景反馈。底部说明及构建号替换为单个 globe 官网链接：`https://type.roarkist.com/`。
- 菜单图标：Build 48 的实机截图测得 ABC 44×32 px、R 28×32 px。只读探针确认 `.Hans` 同时有 `Primary=R` 与指向 24×16 PDF 的 `TISPropertyIconImageURL`。Build 49 移除三个显式 menu/alternate/palette 图标键，仅保留系统字母标签，避免继续把 PDF 几何检查当作系统菜单验收。

## 验证

- 新像素回归 `recordingClockInkIsVerticallyCentered`：0:00、0:08、0:59、1:00、9:59 在修改前全部偏离 4 px；修改后全部在 1 px 容差内。
- `scripts/test.sh` 通过，71 项 Swift Testing 测试通过。
- 原生浅深色设置预览、录音条渲染已检查；这些预览不测试真实麦克风，也不证明活动窗口中的系统焦点环行为。
- 签名、GPU/XPC/权限元数据构建检查通过。提取安装包验证宿主和 helper 均为 49，`.Hans` 标签为 R，三个图片键均不存在。
- 公证 Accepted：`6ae268be-135d-42fd-9a68-28726f495493`。Stapling 与 Gatekeeper 通过。

## 实机结果：图标方案失败，已由 Build 50 回退

已确认安装 Build 49，注册信息中旧 PDF URL 消失，但菜单进程先缓存了旧 R。刷新菜单进程后出现了系统通用输入法图标，而不是 R。用户截图 `image-1788694028805.png` 记录了该结果。因此，`TISIconLabels.Primary = R` 并不能在此第三方输入法上独立替代显式图片；该方案没有解决宽度。不得再把标签已注册等同于系统已经绘制 R。Build 50 恢复显式 R 图片，保留侧栏和计时修正。

以下为当时的验收计划，不代表已通过：

## 原验收计划

- 安装后先确认当前宿主/helper 版本，再检查注册的 `.Hans` 不再返回旧 PDF URL。
- 真正菜单中的 R 宽度必须再与 ABC 对比；目前只有 Build 48 的失败基线，不能声称 Build 49 已达到 44×32 px。
- 若仍返回旧图片 URL，先区分注册/进程缓存，不继续盲目扩大 PDF。
- 验证活动设置窗口不出现蓝框、键盘导航仍可用，以及官网图标能打开正确地址。

深色菜单截图比较命令：

```sh
swift Tests/MenuIcon/CompareScreenshot.swift screenshot.png ax ay aw ah rx ry rw rh --light-badge
```

日志：`/tmp/rotype-release-0.0.1-b49/`。设置预览：`/tmp/rotype-b49-preview/`。
安装包：`~/Downloads/洛克输入法-0.0.1-build49-macOS-arm64.pkg`。
官网仍提供 Build 48，未替换其版本化安装包或对应源码归档。
