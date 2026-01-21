import Foundation

/// Parses and generates hosts file content
public struct HostsParser: Sendable {
    public init() {}

    // MARK: - Parsing

    /// Parse a hosts file string into entries
    public func parse(_ content: String) -> [HostsLine] {
        var lines: [HostsLine] = []
        let rawLines = content.components(separatedBy: .newlines)

        for (index, line) in rawLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                lines.append(.blank)
                continue
            }

            if let entry = parseEntry(line, lineNumber: index + 1) {
                lines.append(.entry(entry))
            } else if trimmed.hasPrefix("#") {
                let commentText = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                lines.append(.comment(HostComment(text: commentText, lineNumber: index + 1)))
            } else {
                // Invalid line - treat as comment
                lines.append(.comment(HostComment(text: "INVALID: \(line)", lineNumber: index + 1)))
            }
        }

        return lines
    }

    /// Parse a single line into a HostEntry
    /// Supports both standard hosts format (IP hostname) and domain-only format (just hostname)
    private func parseEntry(_ line: String, lineNumber: Int) -> HostEntry? {
        var workingLine = line.trimmingCharacters(in: .whitespaces)
        var isEnabled = true

        // Check for commented-out entry (disabled)
        if workingLine.hasPrefix("#") {
            let uncommented = String(workingLine.dropFirst()).trimmingCharacters(in: .whitespaces)
            // Check if this looks like a disabled entry (starts with IP after #)
            if looksLikeIPAddress(String(uncommented.prefix(while: { !$0.isWhitespace }))) {
                workingLine = uncommented
                isEnabled = false
            } else {
                // This is a comment, not a disabled entry
                return nil
            }
        }

        // Extract inline comment
        var comment: String? = nil
        if let commentIndex = workingLine.firstIndex(of: "#") {
            let afterHash = workingLine.index(after: commentIndex)
            if afterHash < workingLine.endIndex {
                comment = String(workingLine[afterHash...]).trimmingCharacters(in: .whitespaces)
            }
            workingLine = String(workingLine[..<commentIndex]).trimmingCharacters(in: .whitespaces)
        }

        // Split by whitespace
        let parts = workingLine.split { $0.isWhitespace }.map(String.init)
        guard !parts.isEmpty else { return nil }

        // Handle domain-only format (single hostname per line, no IP)
        if parts.count == 1 {
            let potentialDomain = parts[0]
            // Must look like a domain (contains a dot, valid hostname chars)
            if potentialDomain.contains(".") && isValidHostname(potentialDomain) {
                return HostEntry(
                    ipAddress: "0.0.0.0",
                    hostnames: [potentialDomain],
                    comment: comment,
                    isEnabled: isEnabled,
                    lineNumber: lineNumber
                )
            }
            return nil
        }

        // Standard hosts format: IP hostname [hostname2 ...]
        let ipAddress = parts[0]
        let hostnames = Array(parts.dropFirst())

        // Validate IP address format
        guard isValidIPAddress(ipAddress) else { return nil }

        // Validate hostnames
        let validHostnames = hostnames.filter { isValidHostname($0) }
        guard !validHostnames.isEmpty else { return nil }

        return HostEntry(
            ipAddress: ipAddress,
            hostnames: validHostnames,
            comment: comment,
            isEnabled: isEnabled,
            lineNumber: lineNumber
        )
    }

    // MARK: - Generation

    /// Generate hosts file content from entries
    public func generate(from entries: [HostEntry], header: String? = nil) -> String {
        var lines: [String] = []

        if let header = header {
            lines.append(header)
            lines.append("")
        }

        for entry in entries {
            lines.append(entry.hostsFileLine)
        }

        return lines.joined(separator: "\n")
    }

    /// Generate content from mixed lines (preserves comments and blanks)
    public func generate(from lines: [HostsLine]) -> String {
        lines.map(\.hostsFileLine).joined(separator: "\n")
    }

    // MARK: - Validation

    /// Check if a string looks like it could be an IP address
    private func looksLikeIPAddress(_ string: String) -> Bool {
        // Quick check: starts with digit or colon (IPv6)
        guard let first = string.first else { return false }
        return first.isNumber || first == ":"
    }

    /// Validate IPv4 or IPv6 address format
    public func isValidIPAddress(_ string: String) -> Bool {
        // IPv4
        if isValidIPv4(string) { return true }
        // IPv6
        if isValidIPv6(string) { return true }
        return false
    }

    private func isValidIPv4(_ string: String) -> Bool {
        let parts = string.split(separator: ".")
        guard parts.count == 4 else { return false }

        for part in parts {
            guard let num = Int(part), num >= 0, num <= 255 else { return false }
        }
        return true
    }

    private func isValidIPv6(_ string: String) -> Bool {
        // Basic IPv6 validation
        // Supports full form and :: shorthand
        var address = string.lowercased()

        // Handle ::
        if address.contains("::") {
            let parts = address.components(separatedBy: "::")
            guard parts.count <= 2 else { return false }
        }

        // Remove leading/trailing colons for validation
        address = address.trimmingCharacters(in: CharacterSet(charactersIn: ":"))

        let groups = address.split(separator: ":", omittingEmptySubsequences: false)

        for group in groups where !group.isEmpty {
            guard group.count <= 4 else { return false }
            guard group.allSatisfy({ $0.isHexDigit }) else { return false }
        }

        return true
    }

    /// Validate hostname format
    public func isValidHostname(_ string: String) -> Bool {
        guard !string.isEmpty, string.count <= 253 else { return false }

        let labels = string.split(separator: ".")

        for label in labels {
            guard label.count <= 63 else { return false }
            guard let first = label.first, first.isLetter || first.isNumber else { return false }
            guard label.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return false }
        }

        return true
    }

    // MARK: - Extraction

    /// Extract only the entries from parsed lines
    public func extractEntries(from lines: [HostsLine]) -> [HostEntry] {
        lines.compactMap { line in
            if case .entry(let entry) = line {
                return entry
            }
            return nil
        }
    }

    /// Extract system entries (localhost, etc.)
    public func extractSystemEntries(from entries: [HostEntry]) -> [HostEntry] {
        entries.filter(\.isSystemEntry)
    }

    /// Extract user entries (non-system)
    public func extractUserEntries(from entries: [HostEntry]) -> [HostEntry] {
        entries.filter { !$0.isSystemEntry }
    }

    // MARK: - Merging

    /// Merge profile entries with system hosts, preserving system entries
    public func merge(profile: Profile, systemEntries: [HostEntry]) -> String {
        var lines: [String] = []

        // Header
        lines.append("##")
        lines.append("# Host Database")
        lines.append("#")
        lines.append("# localhost is used to configure the loopback interface")
        lines.append("# when the system is booting.  Do not change this entry.")
        lines.append("##")
        lines.append("# Managed by SaneHosts")
        lines.append("# Profile: \(profile.name)")
        lines.append("# Last modified: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("##")
        lines.append("")

        // System entries
        for entry in systemEntries {
            lines.append(entry.hostsFileLine)
        }
        lines.append("")

        // Profile entries
        lines.append("# ---- Profile: \(profile.name) ----")
        for entry in profile.entries where !entry.isSystemEntry {
            lines.append(entry.hostsFileLine)
        }
        lines.append("# ---- End Profile ----")

        return lines.joined(separator: "\n")
    }
}
