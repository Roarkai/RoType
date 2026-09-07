# 0.0.1 Build 52 — 缩小 R 字母

用户指出 Build 51 底板已正确，但 R 字母仍比 ABC 中的 A 大。用户截图实测：A 字形 16×17 px，旧 R 字形 16×22 px。

## 修改

只调整字形，不改 22×16 pt 底板、圆角和居中位置。独立诊断进程读取当前系统 ABC 的字体样式：12 pt、semibold、wdth=110、opsz=16。生成器使用公开的 NSFont/NSFontDescriptor 接口匹配这些参数，不把诊断用的私有框架链接到产品。

三个图片配置继续保留，资源名为 `rotypeABC22SmallRTemplate.pdf`，避免与旧资源混淆。计时对齐和侧栏修改不变。

## 验证与交付

- 给 `SystemRendererProbe.m` 增加字高约束，防止只验证底板而漏掉大字：Build 51 字高 11 pt 失败；新 R 字高 8 pt 通过。
- 全部脚本测试和 71 项 Swift Testing 测试通过。
- Developer ID 签名、公证、stapling、Gatekeeper 通过。公证 ID：`44e8ab50-ae33-43f6-9596-a6447c236ff0`。
- 已经系统管理员授权安装 Build 52，注册图片路径及 22×16 pt 尺寸正确，已安装应用的 deep/strict 签名校验通过。
- 菜单仍缓存旧字形，只刷新当前用户的 TextInputMenuAgent 后重新截图并目视检查。实机底板：ABC 与 R 均为 **44×32 px**；内部字形：**A 16×17 px，R 14×16 px**。R 不再显得顶满底板，字高与 A 相差 1 px；不同字母的自然宽度不强行拉齐。

日志与实机截图：`/tmp/rotype-release-0.0.1-b52/`。
下载目录已保留安装包、SHA-256 与 `洛克-build52-菜单图标实测.png`。官网仍提供原 Build 48，未替换历史下载或源码。
