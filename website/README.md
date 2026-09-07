# 洛克官网

线上地址：<https://type.roarkist.com/>。

## 实现与设计

独立静态 HTML / CSS；页面不加载 JavaScript、框架、外部字体或分析脚本。配色跟随系统。页面使用黑白灰，产品截图保留原色；只保留按钮反馈，并尊重减少动态效果偏好。旧版 site.js 和分享图仍保留以兼容已有资源链接。

首页只保留原首屏、两张产品图、版本信息和安装步骤；右上角只放 GitHub 与 roarkist.com 图标。隐私和版本说明独立成页。首屏 SwiftUI 预览保持不变，演示状态已标明。下方图片使用用户提供的两张实机截图，只裁除终端背景，不改文字。单次结果截图不代表所有应用的语音输入均已验收。

图标来自 `@tabler/icons` 3.31.0：brand-github 与 world；只自托管两个 SVG，MIT 许可见 `assets/icons/LICENSE.txt`。

参考研究见 `docs/research/2026-09-06-input-method-websites.md`。

## 本地预览和测试

```sh
python3 -m http.server 4173 --bind 127.0.0.1 --directory website
# 另一终端；需 Python playwright 包与 Google Chrome。
python3 Tests/Website/test_site.py
```

测试覆盖 320/390/768/1024/1440px、系统浅深色切换、两个图标的目标地址、首屏标题、键盘展开系统要求、图片完整性、内部链接、无 JS 内容与减少动态效果。公网可传入 `https://type.roarkist.com`；不关闭 CSP，也不测试原生输入法或麦克风。

## 下载材料

`downloads/` 被 Git 忽略。当前固定发布 Build 48，不能把未来构建替换到相同的版本化 URL。

```sh
python3 scripts/package-source.py
cp 'dist/洛克输入法-0.0.1-macOS-arm64.pkg' website/downloads/RoType-0.0.1-build48-arm64.pkg
(cd website/downloads && shasum -a 256 RoType-0.0.1-build48-arm64.pkg > RoType-0.0.1-build48-arm64.pkg.sha256)
```

复制前必须确认 dist 实际是 Build 48 且已完成公证。当前公开包 63,727,808 bytes；SHA-256：

`018d471313643c1f7a5f8bb88df1e42e252d90fbc2bafa68e3b3530e3633240a`

源码归档包含当前工作树的产品代码、构建脚本、上游子模块和额外 Rime 插件源码，记录其版本，不包含 Git 元数据、下载模型、本地研究或签名凭据。Sparkle 上游测试用 PEM/P12 等密钥形状的夹具不打包，其路径记录在归档 manifest；不影响发行目标的编译。SwiftPM 等依赖继续通过项目固定的版本记录获取。归档不是签名私钥的替代品，也没有声称已验证可逐字节复现签名包。

## 部署

服务器需预先通过 webroot 为 `type.roarkist.com` 获取证书。只使用此站点独立的 `/etc/nginx/conf.d/type.roarkist.com.conf`，不替换全局配置或其他站点。证书续期 challenge 根目录是 `/var/www/rotype-acme`。

```sh
DEPLOY_HOST='USER@HOST' DEPLOY_KEY='/absolute/path/to/local/key' bash scripts/deploy-website.sh
# 仅改网页时可加 REUSE_DOWNLOADS=1；先核对远端 PKG 与源码哈希，再复制已有下载材料。
```

私钥只在本机用于 SSH，不上传、复制进仓库或写入网页。部署使用 `/var/www/rotype/releases/<UTC timestamp>`，通过 `current` 符号链接切换。保留旧目录和独立配置备份到 `/var/www/rotype/rollback/`。部署脚本先校验配置再 reload，重载失败或源站健康检查持续失败时恢复配置和上一个链接。

当前精简版：`/var/www/rotype/releases/20260906-102331`；前一版保留在 `/var/www/rotype/releases/20260906-093709`。实际站点配置随后增加 `Cache-Control: public, no-transform`，阻止 Cloudflare 自动注入分析 beacon，其他站点与 Cloudflare 全区设置保持不变。严格 CSP 继续只允许本站脚本，不为统计脚本加白名单。

续期 hook：`/etc/letsencrypt/renewal-hooks/deploy/rotype-nginx`，仅在该域名成功续期时验证并 reload Nginx。手工演练应使用 `certbot renew --cert-name type.roarkist.com --dry-run --no-random-sleep-on-renew`，避免默认随机等待。

## 已验证与边界

- 公网 HTTPS、全部内部链接、10 组尺寸/配色浏览器测试通过，无控制台错误。
- 此域名的 Certbot 续期演练通过，现有 certbot-renew.timer 已启用。
- 公开 PKG 完整下载与本地文件 SHA-256 一致；源码归档可下载。
- 隐私、版本、robots、sitemap、分享图返回 200，未知页面返回 404。
- 首版的本地 Lighthouse 四项均为 100；精简版以本轮浏览器与链接检查结果为准，不沿用旧版跑分。
- 初次 reload 后立即检查曾遇到短暂 SNI 拒绝；不更改配置即恢复。部署检查现有有界重试，不降低 TLS 校验。
- 不修改其他输入法、模型、用户学习或桌面输入目标。本次网站验收不等于 Build 48 实机语音验收。
