import Foundation

public struct CloudflareClient: Sendable {
    public var token: String
    public var session: URLSession
    public var baseURL: URL

    public init(token: String, session: URLSession = .shared, baseURL: URL = URL(string: "https://api.cloudflare.com/client/v4")!) {
        self.token = token
        self.session = session
        self.baseURL = baseURL
    }

    public func resolveZoneID(zoneName: String) async throws -> String {
        var components = URLComponents(url: baseURL.appendingPathComponent("zones"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "name", value: zoneName),
            URLQueryItem(name: "status", value: "active")
        ]
        let response: CloudflareListResponse<CloudflareZone> = try await send(url: components.url!)
        guard let zone = response.result.first else {
            throw CFSTError.cloudflare("找不到 zone：\(zoneName)")
        }
        return zone.id
    }

    public func listDNSRecords(zoneID: String, hostname: String) async throws -> [CloudflareDNSRecord] {
        let aRecords = try await listDNSRecords(zoneID: zoneID, hostname: hostname, type: .a)
        let aaaaRecords = try await listDNSRecords(zoneID: zoneID, hostname: hostname, type: .aaaa)
        return aRecords + aaaaRecords
    }

    private func listDNSRecords(zoneID: String, hostname: String, type: DNSRecordType) async throws -> [CloudflareDNSRecord] {
        var page = 1
        var all: [CloudflareDNSRecord] = []
        while true {
            var components = URLComponents(url: baseURL.appendingPathComponent("zones/\(zoneID)/dns_records"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "name", value: hostname),
                URLQueryItem(name: "type", value: type.rawValue),
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "page", value: String(page))
            ]
            let response: CloudflareListResponse<CloudflareDNSRecord> = try await send(url: components.url!)
            all.append(contentsOf: response.result)
            if let info = response.resultInfo, page < info.totalPages {
                page += 1
            } else {
                return all
            }
        }
    }

    public func apply(plan: DNSPushPlan, zoneID: String) async throws {
        for create in plan.creates {
            try await createDNSRecord(zoneID: zoneID, operation: create)
        }
        for patch in plan.patches {
            try await patchDNSRecord(zoneID: zoneID, operation: patch)
        }
        for delete in plan.deletes {
            try await deleteDNSRecord(zoneID: zoneID, recordID: delete.record.id)
        }
    }

    public func createDNSRecord(zoneID: String, operation: DNSCreateOperation) async throws {
        let body = DNSRecordMutation(
            type: operation.type,
            name: operation.name,
            content: operation.content,
            ttl: operation.ttl,
            proxied: operation.proxied,
            comment: operation.comment,
            tags: operation.tags
        )
        let _: CloudflareSingleResponse<CloudflareDNSRecord> = try await send(
            url: baseURL.appendingPathComponent("zones/\(zoneID)/dns_records"),
            method: "POST",
            body: body
        )
    }

    public func patchDNSRecord(zoneID: String, operation: DNSPatchOperation) async throws {
        let record = operation.record
        let body = DNSRecordMutation(
            type: record.type,
            name: record.name,
            content: record.content,
            ttl: operation.ttl,
            proxied: operation.proxied,
            comment: operation.clearsComment ? "" : (operation.comment ?? record.comment),
            tags: operation.tags
        )
        let _: CloudflareSingleResponse<CloudflareDNSRecord> = try await send(
            url: baseURL.appendingPathComponent("zones/\(zoneID)/dns_records/\(record.id)"),
            method: "PATCH",
            body: body
        )
    }

    public func deleteDNSRecord(zoneID: String, recordID: String) async throws {
        let _: CloudflareSingleResponse<DeletedRecord> = try await send(
            url: baseURL.appendingPathComponent("zones/\(zoneID)/dns_records/\(recordID)"),
            method: "DELETE",
            body: Optional<EmptyBody>.none
        )
    }

    private func send<T: Decodable>(url: URL, method: String = "GET") async throws -> T {
        try await send(url: url, method: method, body: Optional<EmptyBody>.none)
    }

    private func send<T: Decodable, Body: Encodable>(url: URL, method: String = "GET", body: Body?) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CFSTError.cloudflare("响应无效")
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw CFSTError.cloudflare(message)
        }

        let decoded = try JSONDecoder.cloudflare.decode(T.self, from: data)
        if let envelope = decoded as? CloudflareEnvelopeStatus, !envelope.successValue {
            throw CFSTError.cloudflare(envelope.errorMessage)
        }
        return decoded
    }
}

public struct CloudflareZone: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
}

private struct DNSRecordMutation: Encodable {
    var type: DNSRecordType
    var name: String
    var content: String
    var ttl: Int
    var proxied: Bool
    var comment: String?
    var tags: [String]?
}

private struct DeletedRecord: Codable {
    var id: String
}

private struct EmptyBody: Encodable {}

private protocol CloudflareEnvelopeStatus {
    var successValue: Bool { get }
    var errorMessage: String { get }
}

private struct CloudflareAPIError: Codable {
    var code: Int?
    var message: String
}

private struct ResultInfo: Codable {
    var page: Int
    var perPage: Int
    var count: Int
    var totalCount: Int
    var totalPages: Int
}

private struct CloudflareListResponse<T: Codable>: Codable, CloudflareEnvelopeStatus {
    var success: Bool
    var errors: [CloudflareAPIError]
    var messages: [CloudflareAPIError]?
    var result: [T]
    var resultInfo: ResultInfo?

    var successValue: Bool { success }
    var errorMessage: String { errors.map(\.message).joined(separator: "\n") }
}

private struct CloudflareSingleResponse<T: Codable>: Codable, CloudflareEnvelopeStatus {
    var success: Bool
    var errors: [CloudflareAPIError]
    var messages: [CloudflareAPIError]?
    var result: T

    var successValue: Bool { success }
    var errorMessage: String { errors.map(\.message).joined(separator: "\n") }
}

private extension JSONDecoder {
    static var cloudflare: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
