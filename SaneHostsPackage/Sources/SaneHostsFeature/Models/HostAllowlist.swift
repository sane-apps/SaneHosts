import Foundation

/// Sites the user never wants blocked. An allowed domain also covers its
/// subdomains, so allowing `example.com` unblocks `cdn.example.com`.
/// Only blocking entries are affected; custom redirects are left alone.
public struct HostAllowlist: Codable, Equatable, Sendable {
    public private(set) var domains: [String]

    static let blockingAddresses: Set<String> = ["0.0.0.0", "127.0.0.1", "::", "::1", "0:0:0:0:0:0:0:0"]

    public init(domains: [String] = []) {
        self.domains = []
        for domain in domains {
            add(domain)
        }
    }

    public var isEmpty: Bool {
        domains.isEmpty
    }

    /// Turns pasted input such as `https://www.Example.com/path` or
    /// `*.example.com` into a bare lowercase hostname, or nil if invalid.
    public static func normalize(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let schemeRange = text.range(of: "://") {
            text = String(text[schemeRange.upperBound...])
        }
        if let cut = text.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            text = String(text[..<cut])
        }
        if let at = text.lastIndex(of: "@") {
            text = String(text[text.index(after: at)...])
        }
        if let colon = text.firstIndex(of: ":") {
            text = String(text[..<colon])
        }
        while text.hasPrefix("*.") || text.hasPrefix(".") {
            text = String(text.drop(while: { $0 == "*" || $0 == "." }))
        }
        while text.hasSuffix(".") {
            text.removeLast()
        }
        guard !text.isEmpty, HostsParser().isValidHostname(text), !HostsParser().isValidIPAddress(text) else {
            return nil
        }
        return text
    }

    /// Adds a domain. Returns false when the input is invalid or already listed.
    @discardableResult
    public mutating func add(_ raw: String) -> Bool {
        guard let domain = Self.normalize(raw), !domains.contains(domain) else { return false }
        domains.append(domain)
        domains.sort()
        return true
    }

    public mutating func remove(_ domain: String) {
        domains.removeAll { $0 == domain }
    }

    public func allows(_ hostname: String) -> Bool {
        guard !domains.isEmpty else { return false }
        return Self.allows(hostname, in: Set(domains))
    }

    private static func allows(_ hostname: String, in domainSet: Set<String>) -> Bool {
        var candidate = Substring(hostname.lowercased())
        while true {
            if domainSet.contains(String(candidate)) {
                return true
            }
            guard let dot = candidate.firstIndex(of: ".") else { return false }
            candidate = candidate[candidate.index(after: dot)...]
        }
    }

    /// Removes allowed hostnames from blocking entries. An entry left with no
    /// hostnames is dropped.
    public func apply(to entries: [HostEntry]) -> [HostEntry] {
        guard !domains.isEmpty else { return entries }
        let domainSet = Set(domains)
        return entries.compactMap { entry in
            guard Self.blockingAddresses.contains(entry.ipAddress) else { return entry }
            let kept = entry.hostnames.filter { !Self.allows($0, in: domainSet) }
            guard !kept.isEmpty else { return nil }
            guard kept.count != entry.hostnames.count else { return entry }
            var trimmed = entry
            trimmed.hostnames = kept
            return trimmed
        }
    }
}
