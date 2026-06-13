import CFSTCore
import Foundation

@main
struct TestRunner {
    static func main() async throws {
        var runner = Runner()
        try runner.run("defaultArgumentGeneration", defaultArgumentGeneration)
        try runner.run("httpingAndAdvancedArgumentGeneration", httpingAndAdvancedArgumentGeneration)
        try runner.run("candidateCountAllowsDocumentedLargerValues", candidateCountAllowsDocumentedLargerValues)
        try runner.run("templateValidationRejectsBadValues", templateValidationRejectsBadValues)
        try runner.run("csvParsing", csvParsing)
        try runner.run("csvParsingWithBOM", csvParsingWithBOM)
        try runner.run("csvParsingWithoutColo", csvParsingWithoutColo)
        try runner.run("csvParsingRejectsMissingColumn", csvParsingRejectsMissingColumn)
        try runner.run("settingsStoreRoundTripDoesNotNeedToken", settingsStoreRoundTripDoesNotNeedToken)
        try runner.run("appendPlanPreservesExistingRecordsAndPatchesDuplicateFromOtherProfile", appendPlanPreservesExistingRecordsAndPatchesDuplicateFromOtherProfile)
        try runner.run("appendPlanDoesNotAdoptUnmanagedDuplicate", appendPlanDoesNotAdoptUnmanagedDuplicate)
        try runner.run("appendPlanDoesNotAdoptLooseCommentDuplicate", appendPlanDoesNotAdoptLooseCommentDuplicate)
        try runner.run("appendTaggedRecordPreservesUserComment", appendTaggedRecordPreservesUserComment)
        try runner.run("replaceCurrentProfileDoesNotDeleteOtherProfilesOrManualRecords", replaceCurrentProfileDoesNotDeleteOtherProfilesOrManualRecords)
        try runner.run("replaceSharedRecordRemovesOnlyCurrentProfileTag", replaceSharedRecordRemovesOnlyCurrentProfileTag)
        try runner.run("replaceSharedRecordCanClearCommentWhenRemainingProfileUsesTags", replaceSharedRecordCanClearCommentWhenRemainingProfileUsesTags)
        try runner.run("replaceSharedTaggedRecordPreservesUserComment", replaceSharedTaggedRecordPreservesUserComment)
        try runner.run("replaceKeepsSelectedCurrentRecord", replaceKeepsSelectedCurrentRecord)
        try runner.run("metadataUsesCommentFallback", metadataUsesCommentFallback)
        try runner.run("patchUpdatesTTLAndProxyForExistingRecord", patchUpdatesTTLAndProxyForExistingRecord)
        try await runner.run("cloudflarePatchUsesOperationTTLAndProxy", cloudflarePatchUsesOperationTTLAndProxy)
        try await runner.run("cloudflarePatchCanClearComment", cloudflarePatchCanClearComment)
        try runner.run("rejectInvalidTTL", rejectInvalidTTL)
        try runner.run("normalizeRepairsStaleProfileTemplateBeforeSelection", normalizeRepairsStaleProfileTemplateBeforeSelection)
        runner.finish()
    }

    static func defaultArgumentGeneration() throws {
        let template = SpeedTestTemplate.defaultIPv4()
        let args = try template.makeArguments(outputPath: "/tmp/result.csv", ipFilePath: "/bundle/ip.txt")
        try expect(Array(args[0...1]) == ["-n", "200"])
        try expect(args.contains("-dn"))
        try expect(args.contains("10"))
        try expect(args.contains("-o"))
        try expect(args.contains("/tmp/result.csv"))
        try expect(args.contains("-f"))
        try expect(args.contains("/bundle/ip.txt"))
        try expect(!args.contains("-httping"))
    }

    static func httpingAndAdvancedArgumentGeneration() throws {
        var template = SpeedTestTemplate.defaultHTTPing()
        template.httpingStatusCode = "200"
        template.cfColo = "HKG,NRT"
        template.customIPText = "1.1.1.1,2.2.2.0/24"
        template.disableDownload = true
        template.testAll = true
        template.debug = true

        let args = try template.makeArguments(outputPath: "/tmp/result.csv", ipFilePath: "/bundle/ip.txt")
        try expect(args.contains("-httping"))
        try expectArgument(args, "-httping-code", equals: "200")
        try expectArgument(args, "-cfcolo", equals: "HKG,NRT")
        try expectArgument(args, "-ip", equals: "1.1.1.1,2.2.2.0/24")
        try expect(args.contains("-dd"))
        try expect(args.contains("-allip"))
        try expect(args.contains("-debug"))
    }

    static func candidateCountAllowsDocumentedLargerValues() throws {
        var template = SpeedTestTemplate.defaultIPv4()
        template.candidateCount = 20

        let args = try template.makeArguments(outputPath: "/tmp/result.csv", ipFilePath: "/bundle/ip.txt")
        try expectArgument(args, "-dn", equals: "20")
        try expectArgument(args, "-p", equals: "20")
    }

    static func templateValidationRejectsBadValues() throws {
        var template = SpeedTestTemplate.defaultIPv4()
        template.testURL = "ftp://example.com"
        template.candidateCount = 0
        template.routines = 2000
        template.maxLossRate = 2
        let issues = template.validate()
        try expect(issues.contains { $0.field == "testURL" })
        try expect(issues.contains { $0.field == "candidateCount" })
        try expect(issues.contains { $0.field == "routines" })
        try expect(issues.contains { $0.field == "maxLossRate" })
    }

    static func csvParsing() throws {
        let csv = """
        IP 地址,已发送,已接收,丢包率,平均延迟,下载速度(MB/s),地区码
        104.27.200.69,4,4,0.00,146.23,28.64,LAX
        2606:4700::681b:c845,4,3,0.25,121.50,9.30,HKG
        """
        let results = try CSVParser.parseSpeedTestResults(csvText: csv)
        try expect(results.count == 2)
        try expect(results[0].ipAddress == "104.27.200.69")
        try expect(results[0].recordType == .a)
        try expect(results[1].recordType == .aaaa)
        try expect(results[1].received == 3)
        try expect(results[1].lossRate == 0.25)
    }

    static func csvParsingWithBOM() throws {
        let csv = "\u{feff}IP 地址,已发送,已接收,丢包率,平均延迟,下载速度(MB/s)\n104.27.200.69,4,4,0.00,146.23,28.64\n"
        let results = try CSVParser.parseSpeedTestResults(csvText: csv)
        try expect(results.count == 1)
        try expect(results[0].ipAddress == "104.27.200.69")
    }

    static func csvParsingWithoutColo() throws {
        let csv = """
        IP 地址,已发送,已接收,丢包率,平均延迟,下载速度(MB/s)
        104.27.200.69,4,4,0.00,146.23,28.64
        """
        let results = try CSVParser.parseSpeedTestResults(csvText: csv)
        try expect(results.count == 1)
        try expect(results[0].colo == "N/A")
    }

    static func csvParsingRejectsMissingColumn() throws {
        let csv = "IP 地址,已发送\n1.1.1.1,4\n"
        do {
            _ = try CSVParser.parseSpeedTestResults(csvText: csv)
            throw TestFailure("Expected missing column error")
        } catch let error as CFSTError {
            try expect(error == .missingColumn("已接收"))
        }
    }

    static func settingsStoreRoundTripDoesNotNeedToken() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SettingsStore(fileURL: directory.appendingPathComponent("config.json"))
        var settings = AppSettings.defaults()
        settings.dns.hostname = "cdn.example.com"
        settings.templates[0].testURL = "https://speed.example.com/file"

        try store.save(settings)
        let data = try Data(contentsOf: store.fileURL)
        let text = String(data: data, encoding: .utf8) ?? ""
        try expect(!text.localizedCaseInsensitiveContains("token"))

        let loaded = try store.load()
        try expect(loaded.dns.hostname == "cdn.example.com")
        try expect(loaded.templates[0].testURL == "https://speed.example.com/file")
    }

    static func appendPlanPreservesExistingRecordsAndPatchesDuplicateFromOtherProfile() throws {
        let home = LocationProfile(id: UUID(), name: "家里")
        let office = LocationProfile(id: UUID(), name: "公司")
        let existing = [
            CloudflareDNSRecord(
                id: "office-shared",
                type: .a,
                name: "cdn.example.com",
                content: "104.27.200.69",
                ttl: 300,
                proxied: true,
                comment: DNSRecordMetadata.comment(adding: office.id, profileName: "公司")
            ),
            CloudflareDNSRecord(id: "manual", type: .a, name: "cdn.example.com", content: "8.8.8.8")
        ]
        let selected = [
            SpeedTestResult(ipAddress: "104.27.200.69", sent: 4, received: 4, lossRate: 0, averageLatency: 100, downloadSpeed: 10, colo: "LAX"),
            SpeedTestResult(ipAddress: "172.67.60.78", sent: 4, received: 4, lossRate: 0, averageLatency: 110, downloadSpeed: 9, colo: "SEA")
        ]

        let plan = try DNSPushPlanner.makePlan(selectedResults: selected, existingRecords: existing, action: .append, hostname: "cdn.example.com", ttl: 1, proxied: false, profile: home)
        try expect(plan.deletes.count == 0)
        try expect(plan.creates.map(\.content) == ["172.67.60.78"])
        try expect(plan.patches.count == 1)
        try expect(plan.patches[0].comment?.contains(home.id.uuidString.lowercased()) == true)
        try expect(plan.patches[0].ttl == 300)
        try expect(plan.patches[0].proxied == true)
        try expect(plan.unmanagedRecords.map(\.id) == ["manual"])
    }

    static func appendPlanDoesNotAdoptUnmanagedDuplicate() throws {
        let home = LocationProfile(id: UUID(), name: "家里")
        let existing = [
            CloudflareDNSRecord(id: "manual-duplicate", type: .a, name: "cdn.example.com", content: "104.27.200.69", ttl: 1, proxied: false)
        ]
        let selected = [
            SpeedTestResult(ipAddress: "104.27.200.69", sent: 4, received: 4, lossRate: 0, averageLatency: 100, downloadSpeed: 10, colo: "LAX")
        ]

        let plan = try DNSPushPlanner.makePlan(selectedResults: selected, existingRecords: existing, action: .append, hostname: "cdn.example.com", ttl: 300, proxied: true, profile: home)
        try expect(plan.creates.isEmpty)
        try expect(plan.patches.isEmpty)
        try expect(plan.deletes.isEmpty)
        try expect(plan.unmanagedRecords.map(\.id) == ["manual-duplicate"])
        try expect(plan.unmanagedDuplicateRecords.map(\.id) == ["manual-duplicate"])
    }

    static func appendPlanDoesNotAdoptLooseCommentDuplicate() throws {
        let home = LocationProfile(id: UUID(), name: "家里")
        let existing = [
            CloudflareDNSRecord(
                id: "manual-duplicate",
                type: .a,
                name: "cdn.example.com",
                content: "104.27.200.69",
                comment: "do not touch cfst-manager"
            )
        ]
        let selected = [
            SpeedTestResult(ipAddress: "104.27.200.69", sent: 4, received: 4, lossRate: 0, averageLatency: 100, downloadSpeed: 10, colo: "LAX")
        ]

        let plan = try DNSPushPlanner.makePlan(selectedResults: selected, existingRecords: existing, action: .append, hostname: "cdn.example.com", ttl: 300, proxied: true, profile: home)
        try expect(plan.creates.isEmpty)
        try expect(plan.patches.isEmpty)
        try expect(plan.unmanagedRecords.map(\.id) == ["manual-duplicate"])
        try expect(plan.unmanagedDuplicateRecords.map(\.id) == ["manual-duplicate"])
    }

    static func appendTaggedRecordPreservesUserComment() throws {
        let home = LocationProfile(id: UUID(), name: "家里")
        let office = LocationProfile(id: UUID(), name: "公司")
        let existing = [
            CloudflareDNSRecord(
                id: "office-shared",
                type: .a,
                name: "cdn.example.com",
                content: "104.27.200.69",
                comment: "manual note",
                tags: [
                    DNSRecordMetadata.managedTag,
                    DNSRecordMetadata.profileTag(office.id)
                ]
            )
        ]
        let selected = [
            SpeedTestResult(ipAddress: "104.27.200.69", sent: 4, received: 4, lossRate: 0, averageLatency: 100, downloadSpeed: 10, colo: "LAX")
        ]

        let plan = try DNSPushPlanner.makePlan(selectedResults: selected, existingRecords: existing, action: .append, hostname: "cdn.example.com", ttl: 1, proxied: false, profile: home)
        try expect(plan.patches.count == 1)
        try expect(plan.patches[0].comment == nil)
        try expect(plan.patches[0].clearsComment == false)
        try expect(plan.patches[0].tags?.contains(DNSRecordMetadata.profileTag(home.id)) == true)
        try expect(plan.patches[0].tags?.contains(DNSRecordMetadata.profileTag(office.id)) == true)
    }

    static func replaceCurrentProfileDoesNotDeleteOtherProfilesOrManualRecords() throws {
        let home = LocationProfile(id: UUID(), name: "家里")
        let office = LocationProfile(id: UUID(), name: "公司")
        let existing = [
            CloudflareDNSRecord(
                id: "home-old",
                type: .a,
                name: "cdn.example.com",
                content: "104.27.1.1",
                comment: DNSRecordMetadata.comment(adding: home.id, profileName: "家里")
            ),
            CloudflareDNSRecord(
                id: "office-old",
                type: .a,
                name: "cdn.example.com",
                content: "104.27.2.2",
                comment: DNSRecordMetadata.comment(adding: office.id, profileName: "公司")
            ),
            CloudflareDNSRecord(id: "manual", type: .a, name: "cdn.example.com", content: "8.8.8.8")
        ]
        let selected = [
            SpeedTestResult(ipAddress: "172.67.60.78", sent: 4, received: 4, lossRate: 0, averageLatency: 110, downloadSpeed: 9, colo: "SEA")
        ]

        let plan = try DNSPushPlanner.makePlan(selectedResults: selected, existingRecords: existing, action: .replaceCurrentProfile, hostname: "cdn.example.com", ttl: 1, proxied: false, profile: home)
        try expect(plan.deletes.map { $0.record.id } == ["home-old"])
        try expect(plan.creates.map(\.content) == ["172.67.60.78"])
        try expect(plan.otherProfileRecords.map(\.id) == ["office-old"])
        try expect(plan.unmanagedRecords.map(\.id) == ["manual"])
    }

    static func replaceSharedRecordRemovesOnlyCurrentProfileTag() throws {
        let home = LocationProfile(id: UUID(), name: "家里")
        let office = LocationProfile(id: UUID(), name: "公司")
        let sharedComment = DNSRecordMetadata.comment(
            adding: office.id,
            profileName: "公司",
            existing: DNSRecordMetadata.comment(adding: home.id, profileName: "家里")
        )
        let existing = [
            CloudflareDNSRecord(id: "shared", type: .a, name: "cdn.example.com", content: "104.27.1.1", comment: sharedComment)
        ]

        let plan = try DNSPushPlanner.makePlan(selectedResults: [], existingRecords: existing, action: .replaceCurrentProfile, hostname: "cdn.example.com", ttl: 1, proxied: false, profile: home)
        try expect(plan.deletes.count == 0)
        try expect(plan.patches.count == 1)
        try expect(plan.patches[0].comment?.contains(home.id.uuidString.lowercased()) == false)
        try expect(plan.patches[0].comment?.contains(office.id.uuidString.lowercased()) == true)
    }

    static func replaceSharedRecordCanClearCommentWhenRemainingProfileUsesTags() throws {
        let home = LocationProfile(id: UUID(), name: "家里")
        let office = LocationProfile(id: UUID(), name: "公司")
        let existing = [
            CloudflareDNSRecord(
                id: "shared",
                type: .a,
                name: "cdn.example.com",
                content: "104.27.1.1",
                comment: DNSRecordMetadata.comment(adding: home.id, profileName: "家里"),
                tags: [
                    DNSRecordMetadata.managedTag,
                    DNSRecordMetadata.profileTag(home.id),
                    DNSRecordMetadata.profileTag(office.id)
                ]
            )
        ]

        let plan = try DNSPushPlanner.makePlan(selectedResults: [], existingRecords: existing, action: .replaceCurrentProfile, hostname: "cdn.example.com", ttl: 1, proxied: false, profile: home)
        try expect(plan.deletes.isEmpty)
        try expect(plan.patches.count == 1)
        try expect(plan.patches[0].comment == nil)
        try expect(plan.patches[0].clearsComment)
        try expect(plan.patches[0].tags?.contains(DNSRecordMetadata.profileTag(home.id)) == false)
        try expect(plan.patches[0].tags?.contains(DNSRecordMetadata.profileTag(office.id)) == true)
    }

    static func replaceSharedTaggedRecordPreservesUserComment() throws {
        let home = LocationProfile(id: UUID(), name: "家里")
        let office = LocationProfile(id: UUID(), name: "公司")
        let existing = [
            CloudflareDNSRecord(
                id: "shared",
                type: .a,
                name: "cdn.example.com",
                content: "104.27.1.1",
                comment: "manual note",
                tags: [
                    DNSRecordMetadata.managedTag,
                    DNSRecordMetadata.profileTag(home.id),
                    DNSRecordMetadata.profileTag(office.id)
                ]
            )
        ]

        let plan = try DNSPushPlanner.makePlan(selectedResults: [], existingRecords: existing, action: .replaceCurrentProfile, hostname: "cdn.example.com", ttl: 1, proxied: false, profile: home)
        try expect(plan.patches.count == 1)
        try expect(plan.patches[0].comment == nil)
        try expect(plan.patches[0].clearsComment == false)
        try expect(plan.patches[0].tags?.contains(DNSRecordMetadata.profileTag(home.id)) == false)
        try expect(plan.patches[0].tags?.contains(DNSRecordMetadata.profileTag(office.id)) == true)
    }

    static func replaceKeepsSelectedCurrentRecord() throws {
        let home = LocationProfile(id: UUID(), name: "家里")
        let existing = [
            CloudflareDNSRecord(
                id: "home-current",
                type: .a,
                name: "cdn.example.com",
                content: "104.27.1.1",
                comment: DNSRecordMetadata.comment(adding: home.id, profileName: "家里")
            )
        ]
        let selected = [
            SpeedTestResult(ipAddress: "104.27.1.1", sent: 4, received: 4, lossRate: 0, averageLatency: 100, downloadSpeed: 8, colo: "LAX")
        ]

        let plan = try DNSPushPlanner.makePlan(selectedResults: selected, existingRecords: existing, action: .replaceCurrentProfile, hostname: "cdn.example.com", ttl: 1, proxied: false, profile: home)
        try expect(plan.deletes.isEmpty)
        try expect(plan.creates.isEmpty)
        try expect(plan.patches.isEmpty)
    }

    static func metadataUsesCommentFallback() throws {
        let profileID = UUID()
        let metadata = DNSRecordMetadata.update(adding: profileID, profileName: "家里")
        try expect(metadata.tags == nil)
        try expect(metadata.comment?.contains(profileID.uuidString.lowercased()) == true)
    }

    static func patchUpdatesTTLAndProxyForExistingRecord() throws {
        let home = LocationProfile(id: UUID(), name: "家里")
        let existing = [
            CloudflareDNSRecord(
                id: "home-current",
                type: .a,
                name: "cdn.example.com",
                content: "104.27.1.1",
                ttl: 1,
                proxied: true,
                comment: DNSRecordMetadata.comment(adding: home.id, profileName: "家里")
            )
        ]
        let selected = [
            SpeedTestResult(ipAddress: "104.27.1.1", sent: 4, received: 4, lossRate: 0, averageLatency: 100, downloadSpeed: 8, colo: "LAX")
        ]

        let plan = try DNSPushPlanner.makePlan(selectedResults: selected, existingRecords: existing, action: .append, hostname: "cdn.example.com", ttl: 300, proxied: false, profile: home)
        try expect(plan.patches.count == 1)
        try expect(plan.patches[0].ttl == 300)
        try expect(plan.patches[0].proxied == false)
    }

    static func cloudflarePatchUsesOperationTTLAndProxy() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        CapturingProtocol.lastRequestBody = nil
        configuration.protocolClasses = [CapturingProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = CloudflareClient(token: "token", session: session)
        let operation = DNSPatchOperation(
            record: CloudflareDNSRecord(
                id: "record-id",
                type: .a,
                name: "cdn.example.com",
                content: "104.27.1.1",
                ttl: 1,
                proxied: true
            ),
            ttl: 300,
            proxied: false,
            tags: nil,
            comment: "cfst-manager:profiles=\(UUID().uuidString.lowercased())"
        )

        try await client.patchDNSRecord(zoneID: "zone-id", operation: operation)
        let body = try expectJSON(CapturingProtocol.lastRequestBody)
        try expect(body["ttl"] as? Int == 300)
        try expect(body["proxied"] as? Bool == false)
    }

    static func cloudflarePatchCanClearComment() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        CapturingProtocol.lastRequestBody = nil
        configuration.protocolClasses = [CapturingProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = CloudflareClient(token: "token", session: session)
        let operation = DNSPatchOperation(
            record: CloudflareDNSRecord(
                id: "record-id",
                type: .a,
                name: "cdn.example.com",
                content: "104.27.1.1",
                comment: "cfst-manager:profiles=\(UUID().uuidString.lowercased())"
            ),
            ttl: 1,
            proxied: false,
            tags: [DNSRecordMetadata.managedTag],
            comment: nil,
            clearsComment: true
        )

        try await client.patchDNSRecord(zoneID: "zone-id", operation: operation)
        let body = try expectJSON(CapturingProtocol.lastRequestBody)
        try expect(body["comment"] as? String == "")
    }

    static func rejectInvalidTTL() throws {
        do {
            _ = try DNSPushPlanner.makePlan(
                selectedResults: [],
                existingRecords: [],
                action: .append,
                hostname: "cdn.example.com",
                ttl: 30,
                proxied: false,
                profile: LocationProfile(name: "家里")
            )
            throw TestFailure("Expected invalid TTL")
        } catch CFSTError.invalidTTL(30) {
            return
        }
    }

    static func normalizeRepairsStaleProfileTemplateBeforeSelection() throws {
        let validTemplate = SpeedTestTemplate.defaultIPv4()
        let staleTemplateID = UUID()
        let profile = LocationProfile(name: "家里", defaultTemplateID: staleTemplateID)
        var settings = AppSettings(
            profiles: [profile],
            templates: [validTemplate],
            selectedProfileID: profile.id,
            selectedTemplateID: UUID()
        )

        settings.normalize()
        try expect(settings.profiles[0].defaultTemplateID == validTemplate.id)
        try expect(settings.selectedTemplateID == validTemplate.id)
    }

    static func expectArgument(_ args: [String], _ name: String, equals expected: String) throws {
        guard let index = args.firstIndex(of: name), args.indices.contains(args.index(after: index)) else {
            throw TestFailure("Missing argument \(name)")
        }
        try expect(args[args.index(after: index)] == expected, "\(name) should equal \(expected)")
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String = "Expectation failed") throws {
        guard condition() else { throw TestFailure(message) }
    }

    static func expectJSON(_ data: Data?) throws -> [String: Any] {
        guard let data else {
            throw TestFailure("Missing JSON body")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TestFailure("Invalid JSON body")
        }
        return object
    }
}

struct Runner {
    private var passed = 0

    mutating func run(_ name: String, _ test: () throws -> Void) throws {
        do {
            try test()
            passed += 1
            print("PASS \(name)")
        } catch {
            print("FAIL \(name): \(error)")
            throw error
        }
    }

    mutating func run(_ name: String, _ test: () async throws -> Void) async throws {
        do {
            try await test()
            passed += 1
            print("PASS \(name)")
        } catch {
            print("FAIL \(name): \(error)")
            throw error
        }
    }

    func finish() {
        print("All \(passed) tests passed")
    }
}

struct TestFailure: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}

final class CapturingProtocol: URLProtocol {
    nonisolated(unsafe) static var lastRequestBody: Data?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lastRequestBody = request.httpBody ?? request.httpBodyStream.flatMap(Self.readStream)
        let body = """
        {"success":true,"errors":[],"messages":[],"result":{"id":"record-id","type":"A","name":"cdn.example.com","content":"104.27.1.1","ttl":300,"proxied":false}}
        """.data(using: .utf8)!
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readStream(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }
        return data
    }
}
