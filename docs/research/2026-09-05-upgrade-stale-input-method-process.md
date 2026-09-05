# 升级后动态英文候选缺失

## 现场证据

0.2.27 安装后，菜单身份正确，但用户候选框没有动态英文翻译。翻译服务日志反复记录 Security 错误 `-67034`，即 `the code on disk does not match what is running`。

对当时运行的 Squirrel PID 43383 使用 `SecCodeCopyGuestWithAttributes` 和 `SecCodeCheckValidity`：前者返回 0，后者返回 -67034。磁盘上的应用通过 `codesign --verify --deep --strict`。

正式包 `Squirrel --quit` 没有退出该进程。原因是 `Main.swift` 的退出筛选调用 `isTrustedRoTypeInputMethod`，运行代码与磁盘不一致时筛选失败。此处应与 XPC 授权策略区分：不能为了升级退出而放宽翻译服务的调用者签名校验。

## 本次恢复

定向 TERM 已核实的旧输入法进程，然后通过正式包选择洛克。新 PID 45800 的运行签名检查返回 0。使用开发者证书签名、输入法 identifier 的临时探针连接现有 LaunchAgent，真实请求 `你好`，返回 `zh-en Hello`。

没有删除输入源、用户词典、翻译模型，没有关闭 XPC 签名校验。服务与运行签名已验证恢复；该探针不覆盖真实候选框的 Lua 响应注入和刷新，不能替代 GUI 验收。

## 0.2.29 的升级退出修复

0.2.28 安装后同一故障再次复现，PID 64679 的运行签名返回 -67034。提取退出授权逻辑到 `Squirrel/sources/RoTypeProcessTrust.swift`，由现有 `--quit` 调用，postinstall 无需另加杀进程旁路。

仅当 bundle ID、解析后的准确可执行路径都相同，且运行验证恰好返回 `errSecCSStaticCodeChanged` 时，校验该路径上替换包的完整静态签名及原有 Apple/Team ID/identifier 要求。替换包验证通过才允许退出。其他签名错误继续拒绝；翻译 XPC 的运行签名授权完全不变。

`scripts/test-input-method-upgrade.sh` 创建隔离的 Developer ID 签名测试应用，启动旧进程后原子替换其签名可执行文件。修复前明确失败（预期允许退出，实际拒绝）；修复后验证正常进程、不同路径拒绝、合法替换允许、篡改替换拒绝，以及旧进程真正退出。已接入打包流程，不涉及真实 LaunchAgent 或输入法进程。

使用同一生产退出策略成功终止现场旧进程后，真实翻译再次返回 `zh-en Hello`，临时 NSTextView 窗口的第 9 项实际出现英文候选。完整测试脚本、Squirrel 构建和升级回归通过。

## 图标缓存验收

0.2.28 磁盘图标已为 16 pt，但菜单代理仍是 0.2.27 期间启动的 PID 43800。现场重启菜单代理后，截图确认 16 pt 图标已与电池基本对齐。0.2.29 改用 `rotypeMenu16Template.pdf` 新资源名，避免复用旧 24 pt 图标的缓存键；不把重启系统代理写入安装流程。

0.2.29 已签名、公证；仍需在用户完成本次安装后，确认原生升级流程本身退出了旧进程、运行签名为 0，且菜单/候选框保持正常。这次安装后验收不能由上述隔离测试替代。
