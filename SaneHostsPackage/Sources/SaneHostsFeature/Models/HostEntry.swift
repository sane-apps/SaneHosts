import Foundation

public enum HostsSanitizer {
    public static func comment(_ text: String) -> String {
        text.unicodeScalars
            .map { CharacterSet.newlines.contains($0) || CharacterSet.controlCharacters.contains($0) ? " " : String($0) }
            .joined()
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum HostsContentValidator {
    private static let maxHostsFileBytes = 25 * 1024 * 1024

    public static func validate(_ content: String) throws {
        guard content.utf8.count <= maxHostsFileBytes else {
            throw ValidationError.tooLarge
        }
        guard !content.contains("\0") else {
            throw ValidationError.nulByte
        }

        let parser = HostsParser()
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let contentBeforeComment = trimmed
                .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                .first
                .map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let parts = contentBeforeComment.split { $0.isWhitespace }.map(String.init)

            guard parts.count >= 2, parser.isValidIPAddress(parts[0]) else {
                throw ValidationError.invalidLine
            }
            guard parts.dropFirst().allSatisfy({ parser.isValidHostname($0) }) else {
                throw ValidationError.invalidHostname
            }
        }
    }

    public enum ValidationError: LocalizedError, Equatable {
        case tooLarge
        case nulByte
        case invalidLine
        case invalidHostname

        public var errorDescription: String? {
            switch self {
            case .tooLarge:
                "hosts content is too large"
            case .nulByte:
                "hosts content contains NUL bytes"
            case .invalidLine:
                "hosts content contains an invalid line"
            case .invalidHostname:
                "hosts content contains an invalid hostname"
            }
        }
    }
}

/// Represents a single entry in a hosts file
public struct HostEntry: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var ipAddress: String
    public var hostnames: [String]
    public var comment: String?
    public var isEnabled: Bool

    /// Original line number in the hosts file (for preserving order)
    public var lineNumber: Int?

    public init(
        id: UUID = UUID(),
        ipAddress: String,
        hostnames: [String],
        comment: String? = nil,
        isEnabled: Bool = true,
        lineNumber: Int? = nil
    ) {
        self.id = id
        self.ipAddress = ipAddress
        self.hostnames = hostnames
        self.comment = comment
        self.isEnabled = isEnabled
        self.lineNumber = lineNumber
    }

    /// The primary hostname (first in the list)
    public var primaryHostname: String {
        hostnames.first ?? ""
    }

    /// Format as a hosts file line
    public var hostsFileLine: String {
        var line = ""
        if !isEnabled {
            line += "# "
        }
        line += ipAddress
        line += "\t"
        line += hostnames.joined(separator: " ")
        if let comment = comment {
            let safeComment = HostsSanitizer.comment(comment)
            if !safeComment.isEmpty {
                line += " # \(safeComment)"
            }
        }
        return line
    }

    /// Check if this is a localhost entry (system-critical)
    public var isSystemEntry: Bool {
        let systemHostnames = ["localhost", "broadcasthost", "local"]
        return hostnames.contains { systemHostnames.contains($0.lowercased()) }
    }

    /// Check if this is a loopback address
    public var isLoopback: Bool {
        ipAddress == "127.0.0.1" || ipAddress == "::1"
    }
}

/// Represents a comment-only line in hosts file
public struct HostComment: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var text: String
    public var lineNumber: Int?

    public init(id: UUID = UUID(), text: String, lineNumber: Int? = nil) {
        self.id = id
        self.text = text
        self.lineNumber = lineNumber
    }

    public var hostsFileLine: String {
        "# \(HostsSanitizer.comment(text))"
    }
}

/// A line in a hosts file - either an entry, comment, or blank
public enum HostsLine: Identifiable, Codable, Equatable, Hashable, Sendable {
    case entry(HostEntry)
    case comment(HostComment)
    case blank

    public var id: String {
        switch self {
        case .entry(let entry): return entry.id.uuidString
        case .comment(let comment): return comment.id.uuidString
        case .blank: return UUID().uuidString
        }
    }

    public var hostsFileLine: String {
        switch self {
        case .entry(let entry): return entry.hostsFileLine
        case .comment(let comment): return comment.hostsFileLine
        case .blank: return ""
        }
    }
}
