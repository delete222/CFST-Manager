import Foundation

public enum IPMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case ipv4
    case ipv6

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ipv4: "IPv4"
        case .ipv6: "IPv6"
        }
    }

    public var defaultIPFileName: String {
        switch self {
        case .ipv4: "ip.txt"
        case .ipv6: "ipv6.txt"
        }
    }
}

public enum PingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case tcping
    case httping

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .tcping: "TCPing"
        case .httping: "HTTPing"
        }
    }
}

public struct ValidationIssue: Equatable, Sendable {
    public var field: String
    public var message: String

    public init(field: String, message: String) {
        self.field = field
        self.message = message
    }
}

public struct SpeedTestTemplate: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var ipMode: IPMode
    public var testURL: String
    public var port: Int
    public var candidateCount: Int
    public var routines: Int
    public var pingTimes: Int
    public var downloadTime: Int
    public var maxDelay: Int
    public var minDelay: Int
    public var maxLossRate: Double
    public var minSpeed: Double
    public var pingMode: PingMode
    public var httpingStatusCode: String
    public var cfColo: String
    public var customIPText: String
    public var disableDownload: Bool
    public var testAll: Bool
    public var debug: Bool

    public enum OfficialDefaults {
        public static let routines = 200
        public static let pingTimes = 4
        public static let candidateCount = 10
        public static let downloadTime = 10
        public static let port = 443
        public static let testURL = "https://cf.xiu2.xyz/url"
        public static let maxDelay = 9999
        public static let minDelay = 0
        public static let maxLossRate = 1.0
        public static let minSpeed = 0.0
    }

    public enum OfficialLimits {
        public static let routines = 1...1000
        public static let pingTimes = 1...1000
        public static let candidateCount = 1...1000
        public static let downloadTime = 1...120
        public static let port = 1...65535
        public static let delay = 0...9999
        public static let lossRate = 0.0...1.0
        public static let minSpeed = 0.0...Double.greatestFiniteMagnitude
    }

    public init(
        id: UUID = UUID(),
        name: String,
        ipMode: IPMode,
        testURL: String = OfficialDefaults.testURL,
        port: Int = OfficialDefaults.port,
        candidateCount: Int = OfficialDefaults.candidateCount,
        routines: Int = OfficialDefaults.routines,
        pingTimes: Int = OfficialDefaults.pingTimes,
        downloadTime: Int = OfficialDefaults.downloadTime,
        maxDelay: Int = OfficialDefaults.maxDelay,
        minDelay: Int = OfficialDefaults.minDelay,
        maxLossRate: Double = OfficialDefaults.maxLossRate,
        minSpeed: Double = OfficialDefaults.minSpeed,
        pingMode: PingMode = .tcping,
        httpingStatusCode: String = "",
        cfColo: String = "",
        customIPText: String = "",
        disableDownload: Bool = false,
        testAll: Bool = false,
        debug: Bool = false
    ) {
        self.id = id
        self.name = name
        self.ipMode = ipMode
        self.testURL = testURL
        self.port = port
        self.candidateCount = candidateCount
        self.routines = routines
        self.pingTimes = pingTimes
        self.downloadTime = downloadTime
        self.maxDelay = maxDelay
        self.minDelay = minDelay
        self.maxLossRate = maxLossRate
        self.minSpeed = minSpeed
        self.pingMode = pingMode
        self.httpingStatusCode = httpingStatusCode
        self.cfColo = cfColo
        self.customIPText = customIPText
        self.disableDownload = disableDownload
        self.testAll = testAll
        self.debug = debug
    }

    public static func defaultIPv4() -> SpeedTestTemplate {
        SpeedTestTemplate(name: "Cloudflare IPv4 默认", ipMode: .ipv4)
    }

    public static func defaultIPv6() -> SpeedTestTemplate {
        SpeedTestTemplate(name: "Cloudflare IPv6 默认", ipMode: .ipv6)
    }

    public static func defaultHTTPing() -> SpeedTestTemplate {
        SpeedTestTemplate(name: "HTTPing 自定义测速站", ipMode: .ipv4, pingMode: .httping)
    }

    public func validate() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            issues.append(.init(field: "name", message: "模板名称不能为空"))
        }

        if let components = URLComponents(string: testURL),
           let scheme = components.scheme?.lowercased(),
           (scheme == "http" || scheme == "https"),
           components.host != nil {
            // valid
        } else {
            issues.append(.init(field: "testURL", message: "测速 URL 必须是合法的 http 或 https 地址"))
        }

        if !OfficialLimits.port.contains(port) {
            issues.append(.init(field: "port", message: "端口必须在 1 到 65535 之间"))
        }
        if !OfficialLimits.candidateCount.contains(candidateCount) {
            issues.append(.init(field: "candidateCount", message: "候选数量必须在 1 到 1000 之间"))
        }
        if !OfficialLimits.routines.contains(routines) {
            issues.append(.init(field: "routines", message: "线程数必须在 1 到 1000 之间"))
        }
        if !OfficialLimits.pingTimes.contains(pingTimes) {
            issues.append(.init(field: "pingTimes", message: "延迟测试次数必须在 1 到 1000 之间"))
        }
        if !OfficialLimits.downloadTime.contains(downloadTime) {
            issues.append(.init(field: "downloadTime", message: "下载测速时间必须在 1 到 120 秒之间"))
        }
        if !OfficialLimits.delay.contains(maxDelay) || !OfficialLimits.delay.contains(minDelay) || minDelay > maxDelay {
            issues.append(.init(field: "delay", message: "延迟上下限必须在 0 到 9999 ms 之间，且下限不能大于上限"))
        }
        if !OfficialLimits.lossRate.contains(maxLossRate) {
            issues.append(.init(field: "maxLossRate", message: "丢包率上限必须在 0 到 1 之间"))
        }
        if minSpeed < 0 {
            issues.append(.init(field: "minSpeed", message: "下载速度下限不能为负数"))
        }
        if !httpingStatusCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           Int(httpingStatusCode.trimmingCharacters(in: .whitespacesAndNewlines)) == nil {
            issues.append(.init(field: "httpingStatusCode", message: "HTTPing 状态码必须是数字"))
        }
        return issues
    }

    public func makeArguments(outputPath: String, ipFilePath: String) throws -> [String] {
        let issues = validate()
        guard issues.isEmpty else {
            throw CFSTError.validationFailed(issues)
        }

        var arguments: [String] = [
            "-n", String(routines),
            "-t", String(pingTimes),
            "-dn", String(candidateCount),
            "-p", String(candidateCount),
            "-dt", String(downloadTime),
            "-tp", String(port),
            "-url", testURL,
            "-tl", String(maxDelay),
            "-tll", String(minDelay),
            "-tlr", String(maxLossRate),
            "-sl", String(minSpeed),
            "-f", ipFilePath,
            "-o", outputPath
        ]

        if pingMode == .httping {
            arguments.append("-httping")
            let status = httpingStatusCode.trimmingCharacters(in: .whitespacesAndNewlines)
            if !status.isEmpty {
                arguments.append(contentsOf: ["-httping-code", status])
            }
            let colo = cfColo.trimmingCharacters(in: .whitespacesAndNewlines)
            if !colo.isEmpty {
                arguments.append(contentsOf: ["-cfcolo", colo])
            }
        }

        let ipText = customIPText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ipText.isEmpty {
            arguments.append(contentsOf: ["-ip", ipText])
        }
        if disableDownload {
            arguments.append("-dd")
        }
        if testAll {
            arguments.append("-allip")
        }
        if debug {
            arguments.append("-debug")
        }

        return arguments
    }

    public func commandPreview(outputPath: String = "<app-temp>/result.csv", ipFilePath: String = "<bundle>/ip.txt") -> String {
        let arguments = (try? makeArguments(outputPath: outputPath, ipFilePath: ipFilePath)) ?? []
        return (["cfst"] + arguments).map { argument in
            if argument.contains(where: { $0 == " " || $0 == "\"" }) {
                return "\"" + argument.replacingOccurrences(of: "\"", with: "\\\"") + "\""
            }
            return argument
        }.joined(separator: " ")
    }
}

public struct LocationProfile: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var defaultTemplateID: UUID?

    public init(id: UUID = UUID(), name: String, defaultTemplateID: UUID? = nil) {
        self.id = id
        self.name = name
        self.defaultTemplateID = defaultTemplateID
    }
}

public struct DNSSettings: Codable, Equatable, Sendable {
    public var zoneName: String
    public var zoneID: String
    public var hostname: String
    public var ttl: Int
    public var proxied: Bool

    public init(
        zoneName: String = "",
        zoneID: String = "",
        hostname: String = "",
        ttl: Int = 1,
        proxied: Bool = false
    ) {
        self.zoneName = zoneName
        self.zoneID = zoneID
        self.hostname = hostname
        self.ttl = ttl
        self.proxied = proxied
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var dns: DNSSettings
    public var profiles: [LocationProfile]
    public var templates: [SpeedTestTemplate]
    public var selectedProfileID: UUID?
    public var selectedTemplateID: UUID?

    public init(
        dns: DNSSettings = DNSSettings(),
        profiles: [LocationProfile] = [],
        templates: [SpeedTestTemplate] = [],
        selectedProfileID: UUID? = nil,
        selectedTemplateID: UUID? = nil
    ) {
        self.dns = dns
        self.profiles = profiles
        self.templates = templates
        self.selectedProfileID = selectedProfileID
        self.selectedTemplateID = selectedTemplateID
    }

    public static func defaults() -> AppSettings {
        let ipv4 = SpeedTestTemplate.defaultIPv4()
        let ipv6 = SpeedTestTemplate.defaultIPv6()
        let httping = SpeedTestTemplate.defaultHTTPing()
        let home = LocationProfile(name: "家里", defaultTemplateID: ipv4.id)
        let office = LocationProfile(name: "公司", defaultTemplateID: ipv4.id)
        return AppSettings(
            profiles: [home, office],
            templates: [ipv4, ipv6, httping],
            selectedProfileID: home.id,
            selectedTemplateID: ipv4.id
        )
    }

    public mutating func normalize() {
        if templates.isEmpty {
            templates = [.defaultIPv4(), .defaultIPv6(), .defaultHTTPing()]
        }
        if profiles.isEmpty {
            profiles = [LocationProfile(name: "家里", defaultTemplateID: templates.first?.id)]
        }
        let validTemplateIDs = Set(templates.map(\.id))
        for index in profiles.indices where profiles[index].defaultTemplateID.map({ !validTemplateIDs.contains($0) }) != false {
            profiles[index].defaultTemplateID = templates.first?.id
        }
        if selectedProfileID == nil || !profiles.contains(where: { $0.id == selectedProfileID }) {
            selectedProfileID = profiles.first?.id
        }
        if selectedTemplateID == nil || !templates.contains(where: { $0.id == selectedTemplateID }) {
            let profileDefault = profiles.first(where: { $0.id == selectedProfileID })?.defaultTemplateID
            selectedTemplateID = profileDefault.flatMap { validTemplateIDs.contains($0) ? $0 : nil } ?? templates.first?.id
        }
    }
}

public struct SpeedTestResult: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var ipAddress: String
    public var sent: Int
    public var received: Int
    public var lossRate: Double
    public var averageLatency: Double
    public var downloadSpeed: Double
    public var colo: String
    public var selected: Bool

    public init(
        id: UUID = UUID(),
        ipAddress: String,
        sent: Int,
        received: Int,
        lossRate: Double,
        averageLatency: Double,
        downloadSpeed: Double,
        colo: String,
        selected: Bool = true
    ) {
        self.id = id
        self.ipAddress = ipAddress
        self.sent = sent
        self.received = received
        self.lossRate = lossRate
        self.averageLatency = averageLatency
        self.downloadSpeed = downloadSpeed
        self.colo = colo
        self.selected = selected
    }

    public var recordType: DNSRecordType? {
        IPAddress.recordType(for: ipAddress)
    }
}

public enum DNSRecordType: String, Codable, CaseIterable, Sendable {
    case a = "A"
    case aaaa = "AAAA"
}

public enum DNSPushAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case append
    case replaceCurrentProfile

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .append: "追加选中 IP"
        case .replaceCurrentProfile: "替换当前地点"
        }
    }
}

public struct CloudflareDNSRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var type: DNSRecordType
    public var name: String
    public var content: String
    public var ttl: Int
    public var proxied: Bool?
    public var comment: String?
    public var tags: [String]?

    public init(
        id: String,
        type: DNSRecordType,
        name: String,
        content: String,
        ttl: Int = 1,
        proxied: Bool? = false,
        comment: String? = nil,
        tags: [String]? = nil
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.content = content
        self.ttl = ttl
        self.proxied = proxied
        self.comment = comment
        self.tags = tags
    }
}

public struct DNSRecordMetadataUpdate: Equatable, Sendable {
    public var tags: [String]?
    public var comment: String?

    public init(tags: [String]? = nil, comment: String? = nil) {
        self.tags = tags
        self.comment = comment
    }
}

public enum CFSTError: Error, LocalizedError, Equatable {
    case validationFailed([ValidationIssue])
    case missingColumn(String)
    case invalidCSV(String)
    case invalidIPAddress(String)
    case missingBinary(String)
    case processFailed(Int32, String)
    case invalidTTL(Int)
    case cloudflare(String)
    case keychain(String)
    case missingToken

    public var errorDescription: String? {
        switch self {
        case .validationFailed(let issues):
            return issues.map(\.message).joined(separator: "\n")
        case .missingColumn(let name):
            return "CSV 缺少列：\(name)"
        case .invalidCSV(let reason):
            return "CSV 解析失败：\(reason)"
        case .invalidIPAddress(let ip):
            return "无效 IP：\(ip)"
        case .missingBinary(let path):
            return "找不到内置 CloudflareST：\(path)"
        case .processFailed(let code, let output):
            return "CloudflareST 运行失败（\(code)）：\(output)"
        case .invalidTTL(let ttl):
            return "Cloudflare TTL 无效：\(ttl)。请使用 Auto 或 60 到 86400 秒。"
        case .cloudflare(let message):
            return "Cloudflare API 错误：\(message)"
        case .keychain(let message):
            return "Keychain 错误：\(message)"
        case .missingToken:
            return "请先保存 Cloudflare API Token"
        }
    }
}
