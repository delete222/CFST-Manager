import Foundation
import SwiftUI
import CFSTCore

@MainActor
final class AppViewModel: ObservableObject {
    @Published var settings: AppSettings
    @Published var results: [SpeedTestResult] = []
    @Published var tokenInput = ""
    @Published var tokenSaved = false
    @Published var isRunningTest = false
    @Published var isPushing = false
    @Published var statusMessage = "准备就绪"
    @Published var pushAction: DNSPushAction?
    @Published var existingRecords: [CloudflareDNSRecord] = []
    @Published var latestPlan: DNSPushPlan?

    private let settingsStore: SettingsStore
    private let tokenStore: KeychainTokenStore

    init(settingsStore: SettingsStore = SettingsStore(), tokenStore: KeychainTokenStore = KeychainTokenStore()) {
        self.settingsStore = settingsStore
        self.tokenStore = tokenStore
        do {
            settings = try settingsStore.load()
        } catch {
            settings = .defaults()
            statusMessage = "配置读取失败，已使用默认配置：\(error.localizedDescription)"
        }
        do {
            tokenSaved = try tokenStore.load() != nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    var selectedTemplate: SpeedTestTemplate? {
        get { settings.templates.first { $0.id == settings.selectedTemplateID } }
        set {
            guard let newValue else { return }
            if let index = settings.templates.firstIndex(where: { $0.id == newValue.id }) {
                settings.templates[index] = newValue
                settings.selectedTemplateID = newValue.id
            }
        }
    }

    var selectedProfile: LocationProfile? {
        get { settings.profiles.first { $0.id == settings.selectedProfileID } }
        set {
            guard let newValue else { return }
            if let index = settings.profiles.firstIndex(where: { $0.id == newValue.id }) {
                settings.profiles[index] = newValue
                settings.selectedProfileID = newValue.id
            }
        }
    }

    var selectedResults: [SpeedTestResult] {
        results.filter(\.selected)
    }

    var selectedResultCount: Int {
        selectedResults.count
    }

    var canPreviewOrPush: Bool {
        guard let action = pushAction else {
            return false
        }
        return action == .replaceCurrentProfile || !selectedResults.isEmpty
    }

    var commandPreview: String {
        selectedTemplate?.commandPreview() ?? ""
    }

    func selectProfile(_ id: UUID?) {
        settings.selectedProfileID = id
        if let profile = selectedProfile,
           let templateID = profile.defaultTemplateID,
           settings.templates.contains(where: { $0.id == templateID }) {
            settings.selectedTemplateID = templateID
        }
        clearPushPreview()
        saveSettings()
    }

    func selectTemplate(_ id: UUID?) {
        settings.selectedTemplateID = id
        clearPushPreview()
        saveSettings()
    }

    func setSelectedProfileDefaultTemplate(_ id: UUID?) {
        guard let profileID = settings.selectedProfileID,
              let index = settings.profiles.firstIndex(where: { $0.id == profileID }) else {
            return
        }
        settings.profiles[index].defaultTemplateID = id
        settings.selectedTemplateID = id
        clearPushPreview()
        saveSettings()
    }

    func updatePushAction(_ action: DNSPushAction?) {
        pushAction = action
        clearPushPreview()
    }

    func clearPushPreview() {
        latestPlan = nil
    }

    func saveSettings() {
        do {
            try settingsStore.save(settings)
            statusMessage = "配置已保存"
        } catch {
            statusMessage = "配置保存失败：\(error.localizedDescription)"
        }
    }

    func saveToken() {
        do {
            try tokenStore.save(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines))
            tokenInput = ""
            tokenSaved = true
            statusMessage = "Token 已保存到 Keychain"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func deleteToken() {
        do {
            try tokenStore.delete()
            tokenSaved = false
            statusMessage = "Token 已删除"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func addTemplate() {
        var template = selectedTemplate ?? .defaultIPv4()
        template.id = UUID()
        template.name += " 副本"
        settings.templates.append(template)
        settings.selectedTemplateID = template.id
        saveSettings()
    }

    func newTemplate() {
        let template = SpeedTestTemplate(name: "新测速模板", ipMode: .ipv4)
        settings.templates.append(template)
        settings.selectedTemplateID = template.id
        saveSettings()
    }

    func deleteSelectedTemplate() {
        guard let id = settings.selectedTemplateID, settings.templates.count > 1 else { return }
        settings.templates.removeAll { $0.id == id }
        for index in settings.profiles.indices where settings.profiles[index].defaultTemplateID == id {
            settings.profiles[index].defaultTemplateID = settings.templates.first?.id
        }
        settings.selectedTemplateID = settings.templates.first?.id
        saveSettings()
    }

    func addProfile() {
        let profile = LocationProfile(name: "新地点", defaultTemplateID: settings.selectedTemplateID)
        settings.profiles.append(profile)
        settings.selectedProfileID = profile.id
        saveSettings()
    }

    func deleteSelectedProfile() {
        guard let id = settings.selectedProfileID, settings.profiles.count > 1 else { return }
        settings.profiles.removeAll { $0.id == id }
        settings.selectedProfileID = settings.profiles.first?.id
        saveSettings()
    }

    func toggleResult(_ result: SpeedTestResult) {
        guard let index = results.firstIndex(where: { $0.id == result.id }) else { return }
        results[index].selected.toggle()
        clearPushPreview()
    }

    func setAllResultsSelected(_ selected: Bool) {
        guard results.contains(where: { $0.selected != selected }) else { return }
        for index in results.indices {
            results[index].selected = selected
        }
        clearPushPreview()
    }

    func runSpeedTest() {
        guard let template = selectedTemplate else { return }
        let issues = template.validate()
        guard issues.isEmpty else {
            statusMessage = issues.map(\.message).joined(separator: "\n")
            return
        }

        isRunningTest = true
        statusMessage = "正在运行 CloudflareST..."
        Task {
            do {
                let runner = try CFSTProcessRunner.bundled()
                let run = try await runner.run(template: template)
                results = Array(run.results.prefix(template.candidateCount))
                clearPushPreview()
                statusMessage = "测速完成：\(results.count) 个结果"
            } catch {
                statusMessage = error.localizedDescription
            }
            isRunningTest = false
        }
    }

    func loadSampleResults() {
        let sample = """
        IP 地址,已发送,已接收,丢包率,平均延迟,下载速度(MB/s),地区码
        104.27.200.69,4,4,0.00,146.23,28.64,LAX
        172.67.60.78,4,4,0.00,139.82,15.02,SEA
        104.25.140.153,4,4,0.00,146.49,14.90,SJC
        2606:4700::681b:c845,4,4,0.00,121.50,9.30,HKG
        """
        do {
            results = try CSVParser.parseSpeedTestResults(csvText: sample)
            clearPushPreview()
            statusMessage = "已载入示例结果"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func previewPushPlan() {
        Task {
            do {
                latestPlan = try await makePushPlan(fetchRemote: true)
                statusMessage = "已生成推送预览"
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func pushSelected() {
        guard pushAction != nil else {
            statusMessage = "请选择追加或替换当前地点"
            return
        }
        guard canPreviewOrPush else {
            statusMessage = "追加 IP 时请至少选择一个结果"
            return
        }
        isPushing = true
        statusMessage = "正在推送 DNS 记录..."
        Task {
            do {
                let token = try tokenStore.load() ?? { throw CFSTError.missingToken }()
                let client = CloudflareClient(token: token)
                var dns = settings.dns
                if dns.zoneID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    dns.zoneID = try await client.resolveZoneID(zoneName: dns.zoneName)
                    settings.dns.zoneID = dns.zoneID
                    saveSettings()
                }
                let plan = try await makePushPlan(fetchRemote: true, client: client, zoneID: dns.zoneID)
                try await client.apply(plan: plan, zoneID: dns.zoneID)
                latestPlan = plan
                statusMessage = "DNS 推送完成：新增 \(plan.creates.count)，更新 \(plan.patches.count)，删除 \(plan.deletes.count)"
            } catch {
                statusMessage = error.localizedDescription
            }
            isPushing = false
        }
    }

    private func makePushPlan(fetchRemote: Bool, client: CloudflareClient? = nil, zoneID: String? = nil) async throws -> DNSPushPlan {
        guard let action = pushAction else {
            throw CFSTError.cloudflare("请选择推送动作")
        }
        guard let profile = selectedProfile else {
            throw CFSTError.cloudflare("请选择地点档案")
        }
        guard !settings.dns.hostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CFSTError.cloudflare("请填写目标 hostname")
        }
        var records = existingRecords
        if fetchRemote {
            let usableClient: CloudflareClient
            if let client {
                usableClient = client
            } else {
                let token = try tokenStore.load() ?? { throw CFSTError.missingToken }()
                usableClient = CloudflareClient(token: token)
            }
            let usableZoneID: String
            if let zoneID, !zoneID.isEmpty {
                usableZoneID = zoneID
            } else if !settings.dns.zoneID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                usableZoneID = settings.dns.zoneID
            } else {
                usableZoneID = try await usableClient.resolveZoneID(zoneName: settings.dns.zoneName)
                settings.dns.zoneID = usableZoneID
                saveSettings()
            }
            records = try await usableClient.listDNSRecords(zoneID: usableZoneID, hostname: settings.dns.hostname)
            existingRecords = records
        }
        return try DNSPushPlanner.makePlan(
            selectedResults: selectedResults,
            existingRecords: records,
            action: action,
            hostname: settings.dns.hostname,
            ttl: settings.dns.ttl,
            proxied: settings.dns.proxied,
            profile: profile
        )
    }
}
