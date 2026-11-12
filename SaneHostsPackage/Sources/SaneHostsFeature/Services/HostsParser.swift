import Darwin
import Foundation

public struct HostsParser: Sendable {
    public init() {}

    /// Names that appear in the header of most published hosts files. They
    /// describe the machine itself, so a blocklist import must never block them.
    static let reservedHostnames: Set<String> = [
        "localhost", "localhost.localdomain", "local", "broadcasthost",
        "ip6-localhost", "ip6-loopback", "ip6-localnet", "ip6-mcastprefix",
        "ip6-allnodes", "ip6-allrouters", "ip6-allhosts", "0.0.0.0"
    ]

    // MARK: - Parsing

    public func parse(_ content: String) -> [HostsLine] {
        var lines: [HostsLine] = []
        let rawLines = content.components(separatedBy: .newlines)

        for (index, line) in rawLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                lines.append(.blank)
                continue
            }

            if let entry = parseEntryLine(line, lineNumber: index + 1) {
                lines.append(.entry(entry))
            } else if trimmed.hasPrefix("#") {
                let commentText = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                lines.append(.comment(HostComment(text: commentText, lineNumber: index + 1)))
            } else {
                lines.append(.comment(HostComment(text: "INVALID: \(line)", lineNumber: index + 1)))
            }
        }

        return lines
    }

    /// Parses one hosts line. Accepts `IP host [host ...]`, a bare domain
    /// (common in blocklists, mapped to 0.0.0.0), and `# IP host` as a
    /// disabled entry. Inline `# comments` are split off before hostnames
    /// are read, so comment words never become hostnames.
    public func parseEntryLine(_ line: String, lineNumber: Int? = nil) -> HostEntry? {
        var workingLine = line.trimmingCharacters(in: .whitespaces)
        var isEnabled = true

        if workingLine.hasPrefix("#") {
            let uncommented = String(workingLine.dropFirst()).trimmingCharacters(in: .whitespaces)
            guard looksLikeIPAddress(String(uncommented.prefix(while: { !$0.isWhitespace }))) else {
                return nil
            }
            workingLine = uncommented
            isEnabled = false
        }

        var comment: String?
        if let commentIndex = workingLine.firstIndex(of: "#") {
            let afterHash = workingLine.index(after: commentIndex)
            if afterHash < workingLine.endIndex {
                comment = String(workingLine[afterHash...]).trimmingCharacters(in: .whitespaces)
            }
            workingLine = String(workingLine[..<commentIndex]).trimmingCharacters(in: .whitespaces)
        }

        let parts = workingLine.split { $0.isWhitespace }.map(String.init)
        guard !parts.isEmpty else { return nil }

        if parts.count == 1 {
            let potentialDomain = parts[0]
            guard potentialDomain.contains("."), isValidHostname(potentialDomain) else { return nil }
            return HostEntry(
                ipAddress: "0.0.0.0",
                hostnames: [potentialDomain],
                comment: comment,
                isEnabled: isEnabled,
                lineNumber: lineNumber
            )
        }

        let ipAddress = parts[0]
        guard isValidIPAddress(ipAddress) else { return nil }

        let validHostnames = parts.dropFirst().filter { isValidHostname($0) }
        guard !validHostnames.isEmpty else { return nil }

        return HostEntry(
            ipAddress: ipAddress,
            hostnames: Array(validHostnames),
            comment: comment,
            isEnabled: isEnabled,
            lineNumber: lineNumber
        )
    }

    /// Parses one line of a downloaded blocklist. Skips commented-out lines
    /// and the machine's own names, and drops list comments.
    public func parseBlocklistLine(_ line: String, lineNumber: Int? = nil) -> HostEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("!"), var entry = parseEntryLine(trimmed, lineNumber: lineNumber) else { return nil }
        entry.hostnames.removeAll { Self.reservedHostnames.contains($0.lowercased()) }
        guard !entry.hostnames.isEmpty else { return nil }
        entry.comment = nil
        return entry
    }

    public func parseBlocklist(_ content: String) -> [HostEntry] {
        var entries: [HostEntry] = []
        var lineNumber = 0
        content.enumerateLines { line, _ in
            lineNumber += 1
            if let entry = parseBlocklistLine(line, lineNumber: lineNumber) {
                entries.append(entry)
            }
        }
        return entries
    }

    // MARK: - Generation

    public func generate(from entries: [HostEntry], header: String? = nil) -> String {
        var lines: [String] = []

        if let header {
            lines.append(header)
            lines.append("")
        }

        for entry in entries {
            lines.append(entry.hostsFileLine)
        }

        return lines.joined(separator: "\n")
    }

    public func generate(from lines: [HostsLine]) -> String {
        lines.map(\.hostsFileLine).joined(separator: "\n")
    }

    // MARK: - Validation

    private func looksLikeIPAddress(_ string: String) -> Bool {
        guard let first = string.first else { return false }
        return first.isNumber || first == ":"
    }

    public func isValidIPAddress(_ string: String) -> Bool {
        isValidIPv4(string) || isValidIPv6(string)
    }

    private func isValidIPv4(_ string: String) -> Bool {
        var address = in_addr()
        return string.withCString { inet_pton(AF_INET, $0, &address) == 1 }
    }

    private func isValidIPv6(_ string: String) -> Bool {
        var address = in6_addr()
        return string.withCString { inet_pton(AF_INET6, $0, &address) == 1 }
    }

    public func isValidHostname(_ string: String) -> Bool {
        guard !string.isEmpty, string.count <= 253 else { return false }

        for label in string.split(separator: ".") {
            guard label.count <= 63, let first = label.first, first.isLetter || first.isNumber, label.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return false }
        }

        return true
    }

    // MARK: - Extraction

    public func extractEntries(from lines: [HostsLine]) -> [HostEntry] {
        lines.compactMap { line in
            if case let .entry(entry) = line {
                return entry
            }
            return nil
        }
    }

    public func extractSystemEntries(from entries: [HostEntry]) -> [HostEntry] {
        entries.filter(\.isSystemEntry)
    }

    public func extractUserEntries(from entries: [HostEntry]) -> [HostEntry] {
        entries.filter { !$0.isSystemEntry }
    }

    // MARK: - Merging

    /// Builds the full /etc/hosts text for a profile. System entries stay
    /// first; allowed sites are taken out of blocking entries.
    public func merge(profile: Profile, systemEntries: [HostEntry], allowlist: HostAllowlist = HostAllowlist()) -> String {
        var lines: [String] = []

        let safeProfileName = HostsSanitizer.comment(profile.name)
        lines.append("##")
        lines.append("# Host Database")
        lines.append("#")
        lines.append("# localhost is used to configure the loopback interface")
        lines.append("# when the system is booting.  Do not change this entry.")
        lines.append("##")
        lines.append("# Managed by SaneHosts")
        lines.append("# Profile: \(safeProfileName)")
        lines.append("# Last modified: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("##")
        lines.append("")

        for entry in systemEntries {
            lines.append(entry.hostsFileLine)
        }
        lines.append("")

        lines.append("# ---- Profile: \(safeProfileName) ----")
        for entry in allowlist.apply(to: profile.entries) where !entry.isSystemEntry {
            lines.append(entry.hostsFileLine)
        }
        lines.append("# ---- End Profile ----")

        return lines.joined(separator: "\n")
    }
}
