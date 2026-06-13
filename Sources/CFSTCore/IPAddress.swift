import Foundation

public enum IPAddress {
    public static func recordType(for value: String) -> DNSRecordType? {
        if isIPv4(value) {
            return .a
        }
        if isIPv6(value) {
            return .aaaa
        }
        return nil
    }

    public static func isIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard !part.isEmpty, let number = Int(part), (0...255).contains(number) else {
                return false
            }
            return String(number) == part || part == "0"
        }
    }

    public static func isIPv6(_ value: String) -> Bool {
        guard value.contains(":") else { return false }
        var raw = in6_addr()
        return value.withCString { inet_pton(AF_INET6, $0, &raw) == 1 }
    }
}
