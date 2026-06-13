import SwiftUI
import CFSTCore

struct ContentView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ProfileSettingsView()
                        DNSSettingsView()
                        SpeedTemplateView()
                        ResultsView()
                        PushView()
                    }
                    .padding(20)
                }
                Divider()
                HStack {
                    Text(model.statusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
        }
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        List {
            Section("地点") {
                Picker("当前地点", selection: Binding(
                    get: { model.settings.selectedProfileID },
                    set: { model.selectProfile($0) }
                )) {
                    ForEach(model.settings.profiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }
                .labelsHidden()

                HStack {
                    Button("新增") { model.addProfile() }
                    Button("删除") { model.deleteSelectedProfile() }
                        .disabled(model.settings.profiles.count <= 1)
                }
            }

            Section("模板") {
                Picker("当前模板", selection: Binding(
                    get: { model.settings.selectedTemplateID },
                    set: { model.selectTemplate($0) }
                )) {
                    ForEach(model.settings.templates) { template in
                        Text(template.name).tag(Optional(template.id))
                    }
                }
                .labelsHidden()

                HStack {
                    Button("新建") { model.newTemplate() }
                    Button("复制") { model.addTemplate() }
                    Button("删除") { model.deleteSelectedTemplate() }
                        .disabled(model.settings.templates.count <= 1)
                }
            }

            Section("Token") {
                SecureField("Cloudflare API Token", text: $model.tokenInput)
                HStack {
                    Button("保存") { model.saveToken() }
                        .disabled(model.tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("删除") { model.deleteToken() }
                        .disabled(!model.tokenSaved)
                }
                Text(model.tokenSaved ? "已保存到 Keychain" : "未保存")
                    .foregroundStyle(model.tokenSaved ? .green : .secondary)
            }
        }
        .navigationTitle("CFST Manager")
    }
}

private struct ProfileSettingsView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        GroupBox("地点档案") {
            if let binding = selectedProfileBinding {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("地点名称")
                        TextField("家里 / 公司", text: binding.name)
                        Text("默认模板")
                        Picker("默认模板", selection: Binding(
                            get: { binding.wrappedValue.defaultTemplateID },
                            set: { model.setSelectedProfileDefaultTemplate($0) }
                        )) {
                            ForEach(model.settings.templates) { template in
                                Text(template.name).tag(Optional(template.id))
                            }
                        }
                        .labelsHidden()
                    }
                    GridRow {
                        Text("")
                        Button("保存地点") { model.saveSettings() }
                        Text("")
                        EmptyView()
                    }
                }
            }
        }
    }

    private var selectedProfileBinding: Binding<LocationProfile>? {
        guard let id = model.settings.selectedProfileID,
              let index = model.settings.profiles.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return $model.settings.profiles[index]
    }
}

private struct DNSSettingsView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        GroupBox("Cloudflare DNS") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text("Zone 域名")
                    TextField("example.com", text: dnsBinding(\.zoneName))
                    Text("Zone ID")
                    TextField("可留空自动查询", text: dnsBinding(\.zoneID))
                }
                GridRow {
                    Text("Hostname")
                    TextField("cdn.example.com", text: dnsBinding(\.hostname))
                    Text("TTL")
                    Picker("TTL", selection: dnsBinding(\.ttl)) {
                        Text("Auto").tag(1)
                        Text("60 秒").tag(60)
                        Text("120 秒").tag(120)
                        Text("300 秒").tag(300)
                        Text("600 秒").tag(600)
                        Text("1800 秒").tag(1800)
                        Text("3600 秒").tag(3600)
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("代理")
                    Toggle("DNS only", isOn: Binding(
                        get: { !model.settings.dns.proxied },
                        set: { model.settings.dns.proxied = !$0; model.clearPushPreview() }
                    ))
                    Text("")
                    Button("保存配置") { model.saveSettings() }
                }
            }
        }
    }

    private func dnsBinding<Value>(_ keyPath: WritableKeyPath<DNSSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.settings.dns[keyPath: keyPath] },
            set: {
                model.settings.dns[keyPath: keyPath] = $0
                model.clearPushPreview()
            }
        )
    }
}

private struct SpeedTemplateView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        GroupBox("CloudflareST 测速配置") {
            if let binding = selectedTemplateBinding {
                VStack(alignment: .leading, spacing: 12) {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                        GridRow {
                            Text("模板名称")
                            TextField("模板名称", text: binding.name)
                            Text("IP 类型")
                            Picker("IP 类型", selection: binding.ipMode) {
                                ForEach(IPMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .labelsHidden()
                        }
                        GridRow {
                            Text("测速 URL")
                            TextField("https://cf.xiu2.xyz/url", text: binding.testURL)
                            Text("端口")
                            TextField("443", value: binding.port, format: .number)
                                .frame(width: 80)
                        }
                        GridRow {
                            Text("候选数量")
                            labeledNumberField("数量", unit: "1-1000", value: binding.candidateCount)
                            Text("模式")
                            Picker("模式", selection: binding.pingMode) {
                                ForEach(PingMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .labelsHidden()
                        }
                        GridRow {
                            Text("线程 / 次数")
                            HStack {
                                labeledNumberField("线程", unit: "1-1000", value: binding.routines)
                                labeledNumberField("次数", unit: "1-1000", value: binding.pingTimes)
                                labeledNumberField("下载时间", unit: "秒", value: binding.downloadTime)
                            }
                            Text("筛选")
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 12) {
                                    labeledNumberField("平均延迟下限", unit: "ms", value: binding.minDelay)
                                    labeledNumberField("平均延迟上限", unit: "ms", value: binding.maxDelay)
                                }
                                HStack(spacing: 12) {
                                    labeledNumberField("丢包率上限", unit: "0-1", value: binding.maxLossRate)
                                    labeledNumberField("下载速度下限", unit: "MB/s", value: binding.minSpeed)
                                }
                            }
                        }
                    }

                    DisclosureGroup("高级参数") {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                            GridRow {
                                Text("HTTP 状态码")
                                TextField("例如 200", text: binding.httpingStatusCode)
                                Text("地区码")
                                TextField("HKG,NRT,LAX", text: binding.cfColo)
                            }
                            GridRow {
                                Text("自定义 IP 段")
                                TextField("1.1.1.1,2.2.2.0/24", text: binding.customIPText)
                                Text("开关")
                                HStack {
                                    Toggle("禁用下载", isOn: binding.disableDownload)
                                    Toggle("全量 IPv4", isOn: binding.testAll)
                                    Toggle("Debug", isOn: binding.debug)
                                }
                            }
                        }
                        .padding(.top, 8)
                    }

                    Text(model.commandPreview)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    HStack {
                        Button(model.isRunningTest ? "测速中..." : "开始测速") { model.runSpeedTest() }
                            .disabled(model.isRunningTest)
                        Button("载入示例结果") { model.loadSampleResults() }
                        Button("保存模板") { model.saveSettings() }
                    }
                }
            }
        }
    }

    private var selectedTemplateBinding: Binding<SpeedTestTemplate>? {
        guard let id = model.settings.selectedTemplateID,
              let index = model.settings.templates.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return $model.settings.templates[index]
    }

    private func labeledNumberField(_ title: String, unit: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                TextField(title, value: value, format: .number)
                    .frame(width: 72)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func labeledNumberField(_ title: String, unit: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                TextField(title, value: value, format: .number)
                    .frame(width: 72)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ResultsView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        GroupBox("优选结果") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button("全选") { model.setAllResultsSelected(true) }
                        .disabled(model.results.isEmpty || model.selectedResultCount == model.results.count)
                    Button("全不选") { model.setAllResultsSelected(false) }
                        .disabled(model.results.isEmpty || model.selectedResultCount == 0)
                    Text("已选择 \(model.selectedResultCount) / \(model.results.count)")
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Table(model.results) {
                    TableColumn("选择") { result in
                        Toggle("", isOn: Binding(
                            get: { result.selected },
                            set: { _ in model.toggleResult(result) }
                        ))
                        .labelsHidden()
                    }
                    .width(48)
                    TableColumn("IP") { result in Text(result.ipAddress).textSelection(.enabled) }
                    TableColumn("发送") { result in Text("\(result.sent)") }.width(60)
                    TableColumn("接收") { result in Text("\(result.received)") }.width(60)
                    TableColumn("丢包") { result in Text(String(format: "%.2f", result.lossRate)) }.width(70)
                    TableColumn("延迟 ms") { result in Text(String(format: "%.2f", result.averageLatency)) }.width(80)
                    TableColumn("速度 MB/s") { result in Text(String(format: "%.2f", result.downloadSpeed)) }.width(90)
                    TableColumn("地区") { result in Text(result.colo) }.width(70)
                }
                .frame(minHeight: 180)
            }
        }
    }
}

private struct PushView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        GroupBox("DNS 推送") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("推送动作", selection: Binding(
                    get: { model.pushAction },
                    set: { model.updatePushAction($0) }
                )) {
                    Text("请选择").tag(Optional<DNSPushAction>.none)
                    ForEach(DNSPushAction.allCases) { action in
                        Text(action.displayName).tag(Optional(action))
                    }
                }
                .pickerStyle(.segmented)

                    HStack {
                        Button("预览计划") { model.previewPushPlan() }
                        .disabled(!model.canPreviewOrPush)
                    Button(model.isPushing ? "推送中..." : "推送到 Cloudflare") { model.pushSelected() }
                        .disabled(model.isPushing || !model.canPreviewOrPush)
                }

                if let plan = model.latestPlan {
                    Text("新增 \(plan.creates.count)，更新 \(plan.patches.count)，删除 \(plan.deletes.count)。未管理记录 \(plan.unmanagedRecords.count)，其他地点记录 \(plan.otherProfileRecords.count)。")
                        .foregroundStyle(.secondary)
                    if !plan.unmanagedDuplicateRecords.isEmpty {
                        Text("未处理手动重复记录：\(plan.unmanagedDuplicateRecords.map { $0.content }.joined(separator: ", "))")
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                    }
                    if !plan.deletes.isEmpty {
                        Text("将删除：\(plan.deletes.map { $0.record.content }.joined(separator: ", "))")
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}
