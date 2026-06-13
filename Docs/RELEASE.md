# Release and GitHub Actions

## CI 触发方式

`.github/workflows/build.yml` 会在以下情况运行：

- push 到 `main`
- pull request
- 手动 `workflow_dispatch`
- push `v*` tag

## Jobs

### `Test`

运行：

```sh
swift run CFSTCoreTestRunner
swift build --product CFSTManager
```

### `Package Apple Silicon app`

运行：

```sh
CFST_MANAGER_FORCE_DOWNLOAD=1 CFST_DOWNLOAD_DIR="$PWD/.cache/cfst" Scripts/package_app.sh
ditto -c -k --keepParent "dist/CFST Manager.app" "dist/CFST-Manager-macOS-arm64.zip"
```

然后上传 artifact：

```text
CFST-Manager-macOS-arm64
```

### `Publish release`

只在 `v*` tag 运行。

它会重新打包，并把 `CFST-Manager-macOS-arm64.zip` 上传到 GitHub Release。

## CloudflareSpeedTest 包从哪里来

CI 会从上游 GitHub release 下载：

```text
https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.3.5/cfst_darwin_arm64.zip
```

下载后会校验 SHA-256：

```text
0623f6d24c939e3d3716f556f4d39c7b8781cf6600ee838a1b64e6b2fe4609dc
```

CI 使用 `actions/cache` 缓存：

```text
.cache/cfst/<CloudflareSpeedTest 版本>
```

cache key：

```text
cfst-v2.3.5-darwin-arm64
```

所以同一个 CloudflareSpeedTest 版本通常只下载一次。`Scripts/package_app.sh`
支持用环境变量覆盖上游版本和校验值：

```sh
CFST_VERSION=v2.3.5
CFST_ARM64_ASSETS=cfst_darwin_arm64.zip
CFST_ARM64_SHA256=0623f6d24c939e3d3716f556f4d39c7b8781cf6600ee838a1b64e6b2fe4609dc
```

固定升级默认内置版本时，再更新：

1. `Scripts/package_app.sh` 里的默认 `CFST_VERSION`
2. `Scripts/package_app.sh` 里的默认 SHA-256
3. `.github/workflows/build.yml` 里的 cache key

## 手动检查上游 CFST

`.github/workflows/watch-cfst-upstream.yml` 只支持手动运行，避免定时任务消耗
Actions 免费分钟数和 artifact/cache 存储。

它会执行：

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

如果只是想验证打包链路，可以在 Actions 页面手动运行 `Watch CloudflareSpeedTest`，
并勾选 `force_package`。

## 手动触发一次打包

可以在 GitHub 页面操作：

1. 打开 Actions。
2. 选择 `Build CFST Manager`。
3. 点击 `Run workflow`。

也可以推一个空提交：

```sh
git commit --allow-empty -m "Trigger app package build"
git push
```

## 下载 artifact

网页：

1. 打开某次 Actions run。
2. 页面底部找到 Artifacts。
3. 下载 `CFST-Manager-macOS-arm64`。

命令行：

```sh
gh run download <run-id> --repo delete222/CFST-Manager --dir ./Artifacts
```

下载后会得到：

```text
Artifacts/CFST-Manager-macOS-arm64/CFST-Manager-macOS-arm64.zip
```

普通 push 产生的 artifact 设置为保留 7 天，避免长期占用 Actions artifact 存储。
长期可下载产物应放在 GitHub Release。

## 发布正式版本

创建并推送 tag：

```sh
git tag v0.1.0
git push origin v0.1.0
```

Actions 会创建 GitHub Release，并上传：

```text
CFST-Manager-macOS-arm64.zip
```

## Node.js 20 warning

Workflow 使用：

- `actions/checkout@v5`
- `actions/upload-artifact@v6`
- `actions/cache@v5`

这些版本使用 Node.js 24，避免 GitHub 的 Node.js 20 deprecation warning。

## Apple Silicon-only

第一版只发 Apple Silicon。

`Scripts/package_app.sh` 会检查：

- App 主程序是 arm64。
- 内置 `cfst-darwin-arm64` 是 arm64。

如果在非 Apple Silicon 机器上打包，脚本会失败，避免生成坏包。
