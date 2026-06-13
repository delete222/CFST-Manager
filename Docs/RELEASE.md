# Release and GitHub Actions

## CI 触发方式

仓库只保留一个 GitHub Actions workflow：

```text
.github/workflows/watch-cfst-upstream.yml
```

它只支持手动 `workflow_dispatch`，不会在 push、pull request、tag 或定时任务时自动运行。
这样可以减少 GitHub Actions 免费分钟数消耗，也不会产生需要清理的临时 artifact。

## 手动检查上游 CFST

在 GitHub Actions 页面运行 `Watch CloudflareSpeedTest`：

1. 打开 Actions。
2. 选择 `Watch CloudflareSpeedTest`。
3. 点击 `Run workflow`。
4. 需要强制重新打包当前上游版本时，勾选 `force_package`。

workflow 会执行：

```sh
Scripts/check_cfst_release.sh
```

脚本会：

1. 调用 GitHub API 查询 `XIU2/CloudflareSpeedTest` 最新 release。
2. 比较最新 tag 和 `Scripts/package_app.sh` 当前默认 `CFST_VERSION`。
3. 如果发现新版本，下载 arm64 release zip 并计算 SHA-256。
4. 用最新版本、asset 名和 SHA-256 调用 `Scripts/package_app.sh`。
5. 发布到 GitHub Release：

```text
cfst-<上游版本>
```

如果没有新版本且没有勾选 `force_package`，workflow 只完成检查，不会启动 macOS 打包 job。

## CloudflareSpeedTest 包从哪里来

GitHub Actions 会从上游 release 下载当前选中的 arm64 zip，例如：

```text
https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.3.5/cfst_darwin_arm64.zip
```

下载后会校验 SHA-256：

```text
0623f6d24c939e3d3716f556f4d39c7b8781cf6600ee838a1b64e6b2fe4609dc
```

CI 使用 runner 临时目录：

```sh
CFST_DOWNLOAD_DIR="$RUNNER_TEMP/cfst"
```

不使用 `actions/cache`，也不上传 Actions artifact。长期下载包只放在 GitHub Release。

`Scripts/package_app.sh` 支持用环境变量覆盖上游版本和校验值：

```sh
CFST_VERSION=v2.3.5
CFST_ARM64_ASSETS=cfst_darwin_arm64.zip
CFST_ARM64_SHA256=0623f6d24c939e3d3716f556f4d39c7b8781cf6600ee838a1b64e6b2fe4609dc
```

固定升级默认内置版本时，更新：

1. `Scripts/package_app.sh` 里的默认 `CFST_VERSION`。
2. `Scripts/package_app.sh` 里的默认 SHA-256。

## 发布产物

workflow 会创建或更新 GitHub Release：

```text
cfst-<上游版本>
```

Release asset 命名：

```text
CFST-Manager-macOS-arm64-cfst-<上游版本>.zip
```

已有同名 Release 时，workflow 会用 `gh release upload --clobber` 覆盖同名 asset。

## Node.js 20 warning

Workflow 使用：

- `actions/checkout@v5`

这个版本使用 Node.js 24，避免 GitHub 的 Node.js 20 deprecation warning。

## Apple Silicon-only

第一版只发 Apple Silicon。

`Scripts/package_app.sh` 会检查：

- App 主程序是 arm64。
- 内置 `cfst-darwin-arm64` 是 arm64。

如果在非 Apple Silicon 机器上打包，脚本会失败，避免生成坏包。
