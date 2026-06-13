import Foundation

public struct DNSCreateOperation: Equatable, Sendable {
    public var type: DNSRecordType
    public var name: String
    public var content: String
    public var ttl: Int
    public var proxied: Bool
    public var tags: [String]?
    public var comment: String

    public init(type: DNSRecordType, name: String, content: String, ttl: Int, proxied: Bool, tags: [String]? = nil, comment: String) {
        self.type = type
        self.name = name
        self.content = content
        self.ttl = ttl
        self.proxied = proxied
        self.tags = tags
        self.comment = comment
    }
}

public struct DNSPatchOperation: Equatable, Sendable {
    public var record: CloudflareDNSRecord
    public var ttl: Int
    public var proxied: Bool
    public var tags: [String]?
    public var comment: String?
    public var clearsComment: Bool

    public init(record: CloudflareDNSRecord, ttl: Int, proxied: Bool, tags: [String]? = nil, comment: String? = nil, clearsComment: Bool = false) {
        self.record = record
        self.ttl = ttl
        self.proxied = proxied
        self.tags = tags
        self.comment = comment
        self.clearsComment = clearsComment
    }
}

public struct DNSDeleteOperation: Equatable, Sendable {
    public var record: CloudflareDNSRecord

    public init(record: CloudflareDNSRecord) {
        self.record = record
    }
}

public struct DNSPushPlan: Equatable, Sendable {
    public var creates: [DNSCreateOperation]
    public var patches: [DNSPatchOperation]
    public var deletes: [DNSDeleteOperation]
    public var unmanagedDuplicateRecords: [CloudflareDNSRecord]
    public var unmanagedRecords: [CloudflareDNSRecord]
    public var otherProfileRecords: [CloudflareDNSRecord]
    public var currentProfileRecords: [CloudflareDNSRecord]

    public init(
        creates: [DNSCreateOperation] = [],
        patches: [DNSPatchOperation] = [],
        deletes: [DNSDeleteOperation] = [],
        unmanagedDuplicateRecords: [CloudflareDNSRecord] = [],
        unmanagedRecords: [CloudflareDNSRecord] = [],
        otherProfileRecords: [CloudflareDNSRecord] = [],
        currentProfileRecords: [CloudflareDNSRecord] = []
    ) {
        self.creates = creates
        self.patches = patches
        self.deletes = deletes
        self.unmanagedDuplicateRecords = unmanagedDuplicateRecords
        self.unmanagedRecords = unmanagedRecords
        self.otherProfileRecords = otherProfileRecords
        self.currentProfileRecords = currentProfileRecords
    }
}

public enum DNSPushPlanner {
    public static func makePlan(
        selectedResults: [SpeedTestResult],
        existingRecords: [CloudflareDNSRecord],
        action: DNSPushAction,
        hostname: String,
        ttl: Int,
        proxied: Bool,
        profile: LocationProfile
    ) throws -> DNSPushPlan {
        guard ttl == 1 || (60...86400).contains(ttl) else {
            throw CFSTError.invalidTTL(ttl)
        }

        let targetRecords = existingRecords.filter { record in
            record.name.caseInsensitiveCompare(hostname) == .orderedSame
                && (record.type == .a || record.type == .aaaa)
        }

        let profileID = profile.id
        let selected = try deduplicate(selectedResults.filter(\.selected))
        let selectedKeys = Set(selected.map { recordKey(type: tryRecordType($0), name: hostname, content: $0.ipAddress) })

        var plan = DNSPushPlan()
        for record in targetRecords {
            let profileIDs = DNSRecordMetadata.profileIDs(for: record)
            if profileIDs.contains(profileID) {
                plan.currentProfileRecords.append(record)
            } else if DNSRecordMetadata.isManaged(record) {
                plan.otherProfileRecords.append(record)
            } else {
                plan.unmanagedRecords.append(record)
            }
        }

        var recordsAfterReplace = targetRecords
        if action == .replaceCurrentProfile {
            for record in plan.currentProfileRecords {
                let key = recordKey(type: record.type, name: record.name, content: record.content)
                if selectedKeys.contains(key) {
                    continue
                }
                let profiles = DNSRecordMetadata.profileIDs(for: record)
                if profiles.count <= 1 {
                    plan.deletes.append(.init(record: record))
                    recordsAfterReplace.removeAll { $0.id == record.id }
                } else {
                    let metadata = DNSRecordMetadata.update(removing: profileID, from: record)
                    plan.patches.append(.init(
                        record: record,
                        ttl: record.ttl,
                        proxied: record.proxied ?? false,
                        tags: metadata.tags,
                        comment: metadata.comment,
                        clearsComment: metadata.comment == nil && DNSRecordMetadata.hasManagedComment(record)
                    ))
                }
            }
        }

        for result in selected {
            guard let type = result.recordType else {
                throw CFSTError.invalidIPAddress(result.ipAddress)
            }
            let key = recordKey(type: type, name: hostname, content: result.ipAddress)
            guard selectedKeys.contains(key) else { continue }
            if let unmanagedDuplicate = plan.unmanagedRecords.first(where: { recordKey(type: $0.type, name: $0.name, content: $0.content) == key }) {
                if !plan.unmanagedDuplicateRecords.contains(where: { $0.id == unmanagedDuplicate.id }) {
                    plan.unmanagedDuplicateRecords.append(unmanagedDuplicate)
                }
                continue
            }
            let managedRecordsAfterReplace = recordsAfterReplace.filter(DNSRecordMetadata.isManaged)
            if let existing = managedRecordsAfterReplace.first(where: { recordKey(type: $0.type, name: $0.name, content: $0.content) == key }) {
                let alreadyBelongsToCurrentProfile = DNSRecordMetadata.profileIDs(for: existing).contains(profileID)
                let metadata = DNSRecordMetadata.update(adding: profileID, profileName: profile.name, to: existing)
                let operationTTL = alreadyBelongsToCurrentProfile ? ttl : existing.ttl
                let operationProxied = alreadyBelongsToCurrentProfile ? proxied : (existing.proxied ?? false)
                let ttlChanged = existing.ttl != operationTTL
                let proxiedChanged = (existing.proxied ?? false) != operationProxied
                let tagsChanged = metadata.tags != nil && metadata.tags != (existing.tags ?? []).sorted()
                let commentChanged = metadata.comment != existing.comment
                if ttlChanged || proxiedChanged || tagsChanged || commentChanged || !DNSRecordMetadata.isManaged(existing) {
                    plan.patches.append(.init(
                        record: existing,
                        ttl: operationTTL,
                        proxied: operationProxied,
                        tags: metadata.tags,
                        comment: metadata.comment
                    ))
                }
            } else {
                let metadata = DNSRecordMetadata.update(adding: profileID, profileName: profile.name)
                plan.creates.append(.init(
                    type: type,
                    name: hostname,
                    content: result.ipAddress,
                    ttl: ttl,
                    proxied: proxied,
                    tags: metadata.tags,
                    comment: metadata.comment ?? ""
                ))
            }
        }

        plan.creates.sort { lhs, rhs in
            if lhs.type.rawValue == rhs.type.rawValue {
                return lhs.content < rhs.content
            }
            return lhs.type.rawValue < rhs.type.rawValue
        }
        return plan
    }

    private static func deduplicate(_ results: [SpeedTestResult]) throws -> [SpeedTestResult] {
        var seen: Set<String> = []
        var deduped: [SpeedTestResult] = []
        for result in results {
            guard result.recordType != nil else {
                throw CFSTError.invalidIPAddress(result.ipAddress)
            }
            let key = result.ipAddress.lowercased()
            if seen.insert(key).inserted {
                deduped.append(result)
            }
        }
        return deduped
    }

    private static func tryRecordType(_ result: SpeedTestResult) -> DNSRecordType {
        result.recordType ?? .a
    }

    private static func recordKey(type: DNSRecordType, name: String, content: String) -> String {
        "\(type.rawValue)|\(name.lowercased())|\(content.lowercased())"
    }
}
