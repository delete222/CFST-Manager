# CFST Manager

CFST Manager 是一个 Apple Silicon macOS SwiftUI App，用来运行
[XIU2/CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest)，查看优选 IP 质量，并把选中的 IP 推送到 Cloudflare DNS。

## 能做什么

- 内置 CloudflareSpeedTest `v2.3.5`，打包后双击 `.app` 即可运行。
- GUI 配置 CloudflareSpeedTest 常用参数和高级参数。
- 默认测速参数按 CloudflareSpeedTest 官方默认值：
  `-n 200`、`-t 4`、`-dn 10`、`-dt 10`、`-tp 443`、`-url https://cf.xiu2.xyz/url`、`-tl 9999`、`-tll 0`、`-tlr 1`、`-sl 0`、`-p 10`。
- 测速完成后显示 IP、发送/接收、丢包率、平均延迟、下载速度、地区码。
- 支持结果全选、全不选、单独勾选。
- 支持地点档案，比如家里、公司；每个地点可绑定默认测速模板。
- Cloudflare API Token 保存到 macOS Keychain。
- 普通配置保存到 `~/Library/Application Support/CFST Manager/config.json`。
- DNS 推送必须显式选择：
  - 追加选中 IP
  - 替换当前地点
- 不会自动删除其他地点或手动创建的 DNS 记录。

## 下载和打包

GitHub Actions 只保留一个手动 workflow：`Watch CloudflareSpeedTest`。

它会检查 XIU2/CloudflareSpeedTest 的最新 release。如果上游版本高于当前内置版本，
它会用最新 arm64 release 包打包，并发布到 GitHub Release。为了节省 Actions
免费额度，它不会在 push 时自动打包，也不会每天自动运行，不上传临时 artifact。

如果只是想验证打包链路，可以在 Actions 页面手动运行
`Watch CloudflareSpeedTest`，并勾选 `force_package` 来强制发布当前最新上游版本。

Actions 页面：
https://github.com/delete222/CFST-Manager/actions

## 本地开发

```sh
swift run CFSTCoreTestRunner
swift build --product CFSTManager
LOCAL_CFST_ARM64_DIR=~/Downloads/cfst_darwin_arm64 Scripts/package_app.sh
```

本地打包脚本优先使用：

- `LOCAL_CFST_ARM64_DIR`
- 或 `~/Downloads/cfst_darwin_arm64`

如果没有本地目录，脚本会从 GitHub release 下载 `cfst_darwin_arm64.zip` 并校验 SHA-256。

也可以显式指定上游版本和校验值：

```sh
CFST_VERSION=v2.3.5 \
CFST_ARM64_ASSETS=cfst_darwin_arm64.zip \
CFST_ARM64_SHA256=0623f6d24c939e3d3716f556f4d39c7b8781cf6600ee838a1b64e6b2fe4609dc \
CFST_MANAGER_FORCE_DOWNLOAD=1 \
Scripts/package_app.sh
```

CI 环境会设置：

```sh
CFST_MANAGER_FORCE_DOWNLOAD=1
CFST_DOWNLOAD_DIR="$RUNNER_TEMP/cfst"
```

CloudflareSpeedTest 包会从 GitHub 下载到 runner 临时目录。脚本会在下载目录下按
CloudflareSpeedTest 版本再分一层目录，避免不同上游版本的同名 zip 互相污染。

## 仓库结构

```text
Package.swift
Scripts/package_app.sh
Sources/
  CFSTCore/
  CFSTManagerApp/
  CFSTCoreTestRunner/
Docs/
  DEVELOPER_GUIDE.md
  RELEASE.md
.github/workflows/watch-cfst-upstream.yml
```

核心代码说明见 [Docs/DEVELOPER_GUIDE.md](Docs/DEVELOPER_GUIDE.md)。

发布和 GitHub Actions 说明见 [Docs/RELEASE.md](Docs/RELEASE.md)。

## Cloudflare Token

App 里填写的是 Cloudflare API Token，不是 Global API Key。

建议权限：

- `Zone - Zone - Read`
- `Zone - DNS - Edit`
- Zone Resources 选择目标域名。

## Apple Silicon Only

当前第一版只支持 Apple Silicon macOS。打包脚本会检查 App 主程序和内置 `cfst` 都是 arm64，避免产出架构不匹配的包。

## 上游许可

CFST Manager 打包时会内置 XIU2/CloudflareSpeedTest。

- 上游项目：https://github.com/XIU2/CloudflareSpeedTest
- 上游许可：GPL-3.0

打包产物的 `Contents/Resources/NOTICE.txt` 和 `LICENSE` 会写明来源。
