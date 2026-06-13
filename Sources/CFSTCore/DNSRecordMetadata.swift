import Foundation

public enum DNSRecordMetadata {
    public static let appPrefix = "cfst-manager"
    public static let managedTag = "\(appPrefix):managed"

    public static func profileTag(_ profileID: UUID) -> String {
        "\(appPrefix):profile:\(profileID.uuidString.lowercased())"
    }

    public static func isManaged(_ record: CloudflareDNSRecord) -> Bool {
        let tags = Set((record.tags ?? []).map { $0.lowercased() })
        if tags.contains(managedTag) {
            return true
        }
        return hasManagedComment(record)
    }

    public static func profileIDs(for record: CloudflareDNSRecord) -> Set<UUID> {
        let tags = record.tags ?? []
        let prefix = "\(appPrefix):profile:"
        return Set(tags.compactMap { tag in
            let lowered = tag.lowercased()
            guard lowered.hasPrefix(prefix) else { return nil }
            return UUID(uuidString: String(lowered.dropFirst(prefix.count)))
        }).union(profileIDsFromComment(record.comment))
    }

    public static func hasManagedComment(_ record: CloudflareDNSRecord) -> Bool {
        profileIDsFromComment(record.comment).isEmpty == false
    }

    public static func update(adding profileID: UUID, profileName: String, to record: CloudflareDNSRecord? = nil) -> DNSRecordMetadataUpdate {
        var tags: [String]?
        if record?.tags?.isEmpty == false {
            var tagSet = Set((record?.tags ?? []).filter { !$0.isEmpty })
            tagSet.insert(managedTag)
            tagSet.insert(profileTag(profileID))
            tags = tagSet.sorted()
        }
        let newComment: String?
        if tags != nil, record?.comment != nil, record.map(hasManagedComment) == false {
            newComment = nil
        } else {
            newComment = comment(adding: profileID, profileName: profileName, existing: record?.comment)
        }
        return DNSRecordMetadataUpdate(tags: tags, comment: newComment)
    }

    public static func update(removing profileID: UUID, from record: CloudflareDNSRecord) -> DNSRecordMetadataUpdate {
        let target = profileTag(profileID).lowercased()
        let tags: [String]?
        if record.tags?.isEmpty == false {
            tags = (record.tags ?? []).filter { $0.lowercased() != target }.sorted()
        } else {
            tags = nil
        }
        return DNSRecordMetadataUpdate(
            tags: tags,
            comment: comment(removing: profileID, existing: record.comment)
        )
    }

    public static func comment(adding profileID: UUID, profileName: String, existing: String? = nil) -> String {
        let profileIDs = profileIDsFromComment(existing).union([profileID])
        return "\(appPrefix):profiles=\(profileIDs.map { $0.uuidString.lowercased() }.sorted().joined(separator: ",")); names=\(profileName)"
    }

    public static func comment(removing profileID: UUID, existing: String? = nil) -> String? {
        let profileIDs = profileIDsFromComment(existing).filter { $0 != profileID }
        guard !profileIDs.isEmpty else {
            return nil
        }
        return "\(appPrefix):profiles=\(profileIDs.map { $0.uuidString.lowercased() }.sorted().joined(separator: ","))"
    }

    private static func profileIDsFromComment(_ comment: String?) -> Set<UUID> {
        guard let comment,
              let range = comment.range(of: "\(appPrefix):profiles=", options: .caseInsensitive) else {
            return []
        }
        let tail = comment[range.upperBound...]
        let idsPart = tail.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        return Set(idsPart.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }
}
