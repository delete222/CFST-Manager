# Developer Guide

这份文档给下一个接手的人看。目标是先知道“该从哪里改”，再去读 Swift 代码。

## 总体架构

项目是一个 SwiftPM workspace，分成三个 target：

- `CFSTCore`：核心业务逻辑，不依赖 SwiftUI。
- `CFSTManagerApp`：SwiftUI macOS GUI。
- `CFSTCoreTestRunner`：轻量测试执行器。当前环境没有稳定的 XCTest/Testing，所以用普通 executable 跑断言。

## 主要文件

### `Sources/CFSTCore/Models.swift`

放主要数据结构：

- `SpeedTestTemplate`
- `LocationProfile`
- `DNSSettings`
- `AppSettings`
- `SpeedTestResult`
- `CloudflareDNSRecord`
- `DNSPushAction`

CloudflareSpeedTest 的官方默认参数和输入范围也在这里：

- `SpeedTestTemplate.OfficialDefaults`
- `SpeedTestTemplate.OfficialLimits`

如果要新增 GUI 参数，通常先从这里加字段，再更新：

1. `SpeedTestTemplate.validate()`
2. `SpeedTestTemplate.makeArguments(...)`
3. `ContentView.SpeedTemplateView`
4. `CFSTCoreTestRunner`

### `Sources/CFSTCore/ProcessRunner.swift`

负责启动内置 `cfst-darwin-arm64`：

- 自动创建临时运行目录。
- 自动选择 `ip.txt` 或 `ipv6.txt`。
- 使用 `Process.arguments` 传参，不走 shell 拼接。
- 解析输出目录里的 `result.csv`。

### `Sources/CFSTCore/CSVParser.swift`

解析 CloudflareSpeedTest 的 CSV。

注意点：

- 支持 UTF-8 BOM。
- `地区码` 列可选。
- 支持 IPv4/IPv6。

### `Sources/CFSTCore/CloudflareClient.swift`

Cloudflare API client。

当前用到：

- 查询 zone ID。
- 查询 hostname 下的 A/AAAA 记录。
- 创建 DNS 记录。
- PATCH DNS 记录。
- 删除 DNS 记录。

Token 通过 `Authorization: Bearer <token>` 发送。

### `Sources/CFSTCore/DNSRecordMetadata.swift`

管理本工具写入 DNS 记录的 metadata。

本工具支持两种 metadata：

- DNS record tags：`cfst-manager:managed`、`cfst-manager:profile:<uuid>`
- DNS record comment：`cfst-manager:profiles=<uuid,...>`

安全边界：

- 只有显式 managed tag 或结构化 comment 才算本工具管理。
- 普通用户 comment 即使包含 `cfst-manager` 字样，也不能被当成本工具管理。
- 如果 tags 已能承载 metadata，不覆盖用户原有 comment。

### `Sources/CFSTCore/DNSPushPlanner.swift`

生成 DNS 推送计划，不直接调用网络。

这是最重要的安全边界：

- `append`：保留现有记录，只新增或标记选中 IP。
- `replaceCurrentProfile`：只替换当前地点档案管理过的记录。
- 不删除其他地点记录。
- 不删除手动记录。
- 如果选中的 IP 已经是手动记录，放进 `unmanagedDuplicateRecords`，不自动接管。

改 DNS 行为时优先给这个文件加测试。

### `Sources/CFSTCore/SettingsStore.swift`

保存普通配置到：

```text
~/Library/Application Support/CFST Manager/config.json
```

不要把 Cloudflare Token 放进这里。

### `Sources/CFSTCore/KeychainTokenStore.swift`

保存 Cloudflare API Token 到 macOS Keychain。

### `Sources/CFSTManagerApp/AppViewModel.swift`

SwiftUI 状态管理。

这里负责：

- 加载/保存配置。
- 保存/删除 Token。
- 启动测速。
- 生成 DNS 推送预览。
- 执行 DNS 推送。
- 清理 stale preview。

如果某个 UI 操作会影响 DNS 推送计划，一定要调用 `clearPushPreview()`。

### `Sources/CFSTManagerApp/ContentView.swift`

SwiftUI 界面。

主要分区：

- `SidebarView`
- `ProfileSettingsView`
- `DNSSettingsView`
- `SpeedTemplateView`
- `ResultsView`
- `PushView`

### `Scripts/package_app.sh`

生成：

```text
dist/CFST Manager.app
```

脚本做的事：

1. `swift build -c release --product CFSTManager`
2. 生成 `.app/Contents`
3. 复制主程序
4. 下载或读取 CloudflareSpeedTest
5. 复制 `cfst-darwin-arm64`、`ip.txt`、`ipv6.txt`
6. 写 `NOTICE.txt` 和 `LICENSE`
7. 清理 quarantine
8. ad-hoc codesign

环境变量：

- `LOCAL_CFST_ARM64_DIR`：本地 CloudflareSpeedTest 解压目录。
- `CFST_MANAGER_FORCE_DOWNLOAD=1`：忽略默认本地目录，强制下载。
- `CFST_DOWNLOAD_DIR`：下载 zip 的缓存目录，CI 用 `.cache/cfst`。
- `CFST_VERSION`：覆盖要打包的上游 CloudflareSpeedTest release tag。
- `CFST_ARM64_ASSETS`：覆盖 arm64 release asset 名称，多个候选用逗号分隔。
- `CFST_ARM64_SHA256`：覆盖 arm64 release zip 的 SHA-256。

### `Scripts/check_cfst_release.sh`

查询 XIU2/CloudflareSpeedTest 最新 release，并输出 GitHub Actions 可读的 key/value：

- `current_version`
- `latest_version`
- `cfst_version`
- `asset_name`
- `sha256`
- `update_available`

`.github/workflows/watch-cfst-upstream.yml` 用它来判断上游是否更新；该 workflow
只手动运行，并把产物发布到 GitHub Release。

## 测试

```sh
swift run CFSTCoreTestRunner
swift build --product CFSTManager
LOCAL_CFST_ARM64_DIR=~/Downloads/cfst_darwin_arm64 Scripts/package_app.sh
```

测试覆盖重点：

- CFST 参数生成。
- 配置保存不含 Token。
- CSV 解析。
- DNS append/replace 计划。
- 手动记录不被接管。
- 用户 comment 不被覆盖。
- Cloudflare PATCH body。

## 常见修改点

### 新增一个 CFST 参数

1. 在 `SpeedTestTemplate` 增加字段。
2. 在 `validate()` 增加范围校验。
3. 在 `makeArguments(...)` 生成参数。
4. 在 `SpeedTemplateView` 加 UI。
5. 在测试里断言参数生成。

### 改 DNS 推送规则

1. 先改 `DNSPushPlanner`。
2. 增加测试。
3. 再改 `CloudflareClient.apply(...)` 或 UI 展示。

### 改打包版本

1. 先运行 `Scripts/check_cfst_release.sh` 拿到最新版本和 SHA-256。
2. 更新 `Scripts/package_app.sh` 的默认 `CFST_VERSION`。
3. 更新 `Scripts/package_app.sh` 的默认 SHA-256。
4. 更新 `.github/workflows/build.yml` 的 cache key。
5. 本地和 GitHub Actions 都跑一次。

## Review 要求

每轮非平凡代码修改后运行：

```sh
python3 ~/.codex/skills/autoreview/scripts/autoreview --mode local
```

如果 web search 造成 reviewer 卡住，而改动只涉及本地代码，可以用：

```sh
python3 ~/.codex/skills/autoreview/scripts/autoreview --mode local --no-web-search
```

对 review findings 要先人工核实，确认是真 bug 再修。
