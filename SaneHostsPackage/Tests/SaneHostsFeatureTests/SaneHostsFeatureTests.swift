import Testing
import Foundation
@testable import SaneHostsFeature

// MARK: - HostsParser Tests

@Suite("HostsParser Tests")
struct HostsParserTests {
    let parser = HostsParser()

    // MARK: - Parsing

    @Test("Parse basic hosts entry")
    func parseBasicEntry() {
        let content = "127.0.0.1 localhost"
        let lines = parser.parse(content)

        #expect(lines.count == 1)
        if case .entry(let entry) = lines[0] {
            #expect(entry.ipAddress == "127.0.0.1")
            #expect(entry.hostnames == ["localhost"])
            #expect(entry.isEnabled == true)
            #expect(entry.comment == nil)
        } else {
            Issue.record("Expected entry, got something else")
        }
    }

    @Test("Parse entry with multiple hostnames")
    func parseMultipleHostnames() {
        let content = "127.0.0.1 localhost local myhost"
        let lines = parser.parse(content)

        #expect(lines.count == 1)
        if case .entry(let entry) = lines[0] {
            #expect(entry.hostnames.count == 3)
            #expect(entry.hostnames.contains("localhost"))
            #expect(entry.hostnames.contains("local"))
            #expect(entry.hostnames.contains("myhost"))
        } else {
            Issue.record("Expected entry")
        }
    }

    @Test("Parse entry with inline comment")
    func parseEntryWithComment() {
        let content = "127.0.0.1 example.local # Development server"
        let lines = parser.parse(content)

        if case .entry(let entry) = lines[0] {
            #expect(entry.comment == "Development server")
            #expect(entry.hostnames == ["example.local"])
        } else {
            Issue.record("Expected entry")
        }
    }

    @Test("Parse disabled entry (commented out)")
    func parseDisabledEntry() {
        let content = "# 127.0.0.1 blocked.com"
        let lines = parser.parse(content)

        if case .entry(let entry) = lines[0] {
            #expect(entry.isEnabled == false)
            #expect(entry.ipAddress == "127.0.0.1")
            #expect(entry.hostnames == ["blocked.com"])
        } else {
            Issue.record("Expected disabled entry")
        }
    }

    @Test("Parse pure comment (not disabled entry)")
    func parsePureComment() {
        let content = "# This is just a comment"
        let lines = parser.parse(content)

        if case .comment(let comment) = lines[0] {
            #expect(comment.text == "This is just a comment")
        } else {
            Issue.record("Expected comment, got \(lines[0])")
        }
    }

    @Test("Parse blank lines")
    func parseBlankLines() {
        let content = "127.0.0.1 localhost\n\n192.168.1.1 server"
        let lines = parser.parse(content)

        #expect(lines.count == 3)
        if case .blank = lines[1] {
            // Expected
        } else {
            Issue.record("Expected blank line")
        }
    }

    @Test("Parse full hosts file")
    func parseFullHostsFile() {
        let content = """
        ##
        # Host Database
        ##
        127.0.0.1       localhost
        255.255.255.255 broadcasthost
        ::1             localhost

        # Custom entries
        192.168.1.100   dev.local
        """

        let lines = parser.parse(content)
        let entries = parser.extractEntries(from: lines)

        #expect(entries.count == 4)
        #expect(entries[0].ipAddress == "127.0.0.1")
        #expect(entries[2].ipAddress == "::1")
        #expect(entries[3].ipAddress == "192.168.1.100")
    }

    // MARK: - IP Validation

    @Test("Valid IPv4 addresses")
    func validIPv4() {
        #expect(parser.isValidIPAddress("127.0.0.1") == true)
        #expect(parser.isValidIPAddress("192.168.1.1") == true)
        #expect(parser.isValidIPAddress("0.0.0.0") == true)
        #expect(parser.isValidIPAddress("255.255.255.255") == true)
        #expect(parser.isValidIPAddress("10.0.0.1") == true)
    }

    @Test("Invalid IPv4 addresses")
    func invalidIPv4() {
        #expect(parser.isValidIPAddress("256.0.0.1") == false)
        #expect(parser.isValidIPAddress("127.0.0") == false)
        #expect(parser.isValidIPAddress("127.0.0.1.1") == false)
        #expect(parser.isValidIPAddress("abc.def.ghi.jkl") == false)
    }

    @Test("Valid IPv6 addresses")
    func validIPv6() {
        #expect(parser.isValidIPAddress("::1") == true)
        #expect(parser.isValidIPAddress("fe80::1") == true)
        #expect(parser.isValidIPAddress("2001:db8:85a3::8a2e:370:7334") == true)
        #expect(parser.isValidIPAddress("::") == true)
    }

    @Test("Invalid IPv6 addresses")
    func invalidIPv6() {
        #expect(parser.isValidIPAddress("gggg::1") == false)
    }

    // MARK: - Hostname Validation

    @Test("Valid hostnames")
    func validHostnames() {
        #expect(parser.isValidHostname("localhost") == true)
        #expect(parser.isValidHostname("example.com") == true)
        #expect(parser.isValidHostname("sub.domain.example.com") == true)
        #expect(parser.isValidHostname("my-server") == true)
        #expect(parser.isValidHostname("server1") == true)
    }

    @Test("Invalid hostnames")
    func invalidHostnames() {
        #expect(parser.isValidHostname("") == false)
        #expect(parser.isValidHostname("-invalid") == false)
        #expect(parser.isValidHostname("has spaces.com") == false)
        #expect(parser.isValidHostname(String(repeating: "a", count: 254)) == false)
    }

    // MARK: - Generation

    @Test("Generate hosts file line from entry")
    func generateEntry() {
        let entry = HostEntry(
            ipAddress: "127.0.0.1",
            hostnames: ["example.local"],
            comment: nil
        )

        #expect(entry.hostsFileLine == "127.0.0.1\texample.local")
    }

    @Test("Generate entry with comment")
    func generateEntryWithComment() {
        let entry = HostEntry(
            ipAddress: "127.0.0.1",
            hostnames: ["example.local"],
            comment: "Dev server"
        )

        #expect(entry.hostsFileLine == "127.0.0.1\texample.local # Dev server")
    }

    @Test("Generate disabled entry")
    func generateDisabledEntry() {
        let entry = HostEntry(
            ipAddress: "127.0.0.1",
            hostnames: ["blocked.com"],
            comment: nil,
            isEnabled: false
        )

        #expect(entry.hostsFileLine == "# 127.0.0.1\tblocked.com")
    }

    @Test("Generate from entries array")
    func generateFromEntries() {
        let entries = [
            HostEntry(ipAddress: "127.0.0.1", hostnames: ["localhost"]),
            HostEntry(ipAddress: "192.168.1.1", hostnames: ["server"])
        ]

        let content = parser.generate(from: entries)
        let lines = content.split(separator: "\n")

        #expect(lines.count == 2)
        #expect(lines[0].contains("127.0.0.1"))
        #expect(lines[1].contains("192.168.1.1"))
    }

    // MARK: - Extraction

    @Test("Extract system entries")
    func extractSystemEntries() {
        let entries = [
            HostEntry(ipAddress: "127.0.0.1", hostnames: ["localhost"]),
            HostEntry(ipAddress: "255.255.255.255", hostnames: ["broadcasthost"]),
            HostEntry(ipAddress: "192.168.1.1", hostnames: ["myserver"])
        ]

        let systemEntries = parser.extractSystemEntries(from: entries)

        #expect(systemEntries.count == 2)
        let allAreSystem = systemEntries.allSatisfy { $0.isSystemEntry }
        #expect(allAreSystem)
    }

    @Test("Extract user entries")
    func extractUserEntries() {
        let entries = [
            HostEntry(ipAddress: "127.0.0.1", hostnames: ["localhost"]),
            HostEntry(ipAddress: "192.168.1.1", hostnames: ["myserver"]),
            HostEntry(ipAddress: "10.0.0.1", hostnames: ["devbox"])
        ]

        let userEntries = parser.extractUserEntries(from: entries)

        #expect(userEntries.count == 2)
        let noneAreSystem = userEntries.allSatisfy { !$0.isSystemEntry }
        #expect(noneAreSystem)
    }
}

// MARK: - HostEntry Tests

@Suite("HostEntry Tests")
struct HostEntryTests {

    @Test("Create basic entry")
    func createBasicEntry() {
        let entry = HostEntry(
            ipAddress: "127.0.0.1",
            hostnames: ["localhost"]
        )

        #expect(entry.ipAddress == "127.0.0.1")
        #expect(entry.hostnames == ["localhost"])
        #expect(entry.isEnabled == true)
        #expect(entry.comment == nil)
    }

    @Test("Primary hostname is first hostname")
    func primaryHostname() {
        let entry = HostEntry(
            ipAddress: "127.0.0.1",
            hostnames: ["first", "second", "third"]
        )

        #expect(entry.primaryHostname == "first")
    }

    @Test("System entry detection - localhost")
    func isSystemEntryLocalhost() {
        let entry = HostEntry(ipAddress: "127.0.0.1", hostnames: ["localhost"])
        #expect(entry.isSystemEntry == true)
    }

    @Test("System entry detection - broadcasthost")
    func isSystemEntryBroadcast() {
        let entry = HostEntry(ipAddress: "255.255.255.255", hostnames: ["broadcasthost"])
        #expect(entry.isSystemEntry == true)
    }

    @Test("System entry detection - local")
    func isSystemEntryLocal() {
        let entry = HostEntry(ipAddress: "::1", hostnames: ["local"])
        #expect(entry.isSystemEntry == true)
    }

    @Test("Non-system entry")
    func isNotSystemEntry() {
        let entry = HostEntry(ipAddress: "192.168.1.1", hostnames: ["myserver.local"])
        #expect(entry.isSystemEntry == false)
    }

    @Test("Entry equality")
    func entryEquality() {
        let id = UUID()
        let entry1 = HostEntry(id: id, ipAddress: "127.0.0.1", hostnames: ["localhost"])
        let entry2 = HostEntry(id: id, ipAddress: "127.0.0.1", hostnames: ["localhost"])

        #expect(entry1 == entry2)
    }
}

// MARK: - Profile Tests

@Suite("Profile Tests")
struct ProfileTests {

    @Test("Create basic profile")
    func createBasicProfile() {
        let profile = Profile(name: "Test Profile")

        #expect(profile.name == "Test Profile")
        #expect(profile.entries.isEmpty)
        #expect(profile.isActive == false)
        #expect(profile.source == .local)
    }

    @Test("Profile enabled count")
    func enabledCount() {
        var profile = Profile(name: "Test")
        profile.entries = [
            HostEntry(ipAddress: "127.0.0.1", hostnames: ["a"]),
            HostEntry(ipAddress: "127.0.0.1", hostnames: ["b"], isEnabled: false),
            HostEntry(ipAddress: "127.0.0.1", hostnames: ["c"])
        ]

        #expect(profile.enabledCount == 2)
        #expect(profile.disabledCount == 1)
    }

    @Test("Profile color tags")
    func profileColorTags() {
        let colors = ProfileColor.allCases
        #expect(colors.count == 8)
        #expect(colors.contains(.blue))
        #expect(colors.contains(.red))
        #expect(colors.contains(.green))
    }

    @Test("Profile source display names")
    func profileSourceDisplayNames() {
        #expect(ProfileSource.local.displayName == "Local")
        #expect(ProfileSource.remote(url: URL(string: "https://example.com")!, lastFetched: nil).displayName == "Remote")
        #expect(ProfileSource.system.displayName == "System")
    }

    @Test("Profile source isRemote")
    func profileSourceIsRemote() {
        #expect(ProfileSource.local.isRemote == false)
        #expect(ProfileSource.system.isRemote == false)
        #expect(ProfileSource.remote(url: URL(string: "https://example.com")!, lastFetched: Date()).isRemote == true)
    }
}

// MARK: - ProfileTemplate Tests

@Suite("ProfileTemplate Tests")
struct ProfileTemplateTests {

    @Test("Ad blocking template has entries")
    func adBlockingTemplate() {
        let template = ProfileTemplate.adBlocking
        #expect(template.entries.count > 0)
        #expect(template.name == "Ad Blocking")
    }

    @Test("Development template has local entries")
    func developmentTemplate() {
        let template = ProfileTemplate.development
        #expect(template.entries.count > 0)
        #expect(template.entries.contains { $0.hostnames.contains("local.dev") })
    }

    @Test("Social template blocks social media")
    func socialTemplate() {
        let template = ProfileTemplate.social
        let hostnames = template.entries.flatMap(\.hostnames)
        #expect(hostnames.contains("facebook.com") || hostnames.contains("www.facebook.com"))
    }

    @Test("Privacy template blocks trackers")
    func privacyTemplate() {
        let template = ProfileTemplate.privacy
        let hostnames = template.entries.flatMap(\.hostnames)
        #expect(hostnames.contains("google-analytics.com") || hostnames.contains("analytics.google.com"))
    }

    @Test("All templates have unique names")
    func uniqueTemplateNames() {
        let names = ProfileTemplate.allCases.map(\.name)
        let uniqueNames = Set(names)
        #expect(names.count == uniqueNames.count)
    }
}

// MARK: - HostsLine Tests

@Suite("HostsLine Tests")
struct HostsLineTests {

    @Test("Entry line generates correctly")
    func entryLine() {
        let entry = HostEntry(ipAddress: "127.0.0.1", hostnames: ["localhost"])
        let line = HostsLine.entry(entry)

        #expect(line.hostsFileLine.contains("127.0.0.1"))
        #expect(line.hostsFileLine.contains("localhost"))
    }

    @Test("Comment line generates correctly")
    func commentLine() {
        let comment = HostComment(text: "Test comment", lineNumber: 1)
        let line = HostsLine.comment(comment)

        #expect(line.hostsFileLine == "# Test comment")
    }

    @Test("Blank line generates empty string")
    func blankLine() {
        let line = HostsLine.blank
        #expect(line.hostsFileLine == "")
    }
}

// MARK: - RemoteSyncError Tests

@Suite("RemoteSyncError Tests")
struct RemoteSyncErrorTests {

    @Test("Error descriptions are localized")
    func errorDescriptions() {
        #expect(RemoteSyncError.invalidURL.errorDescription != nil)
        #expect(RemoteSyncError.httpError(404).errorDescription?.contains("404") == true)
        #expect(RemoteSyncError.noValidEntries.errorDescription != nil)
        #expect(RemoteSyncError.timeout.errorDescription != nil)
    }
}

// MARK: - PopularHostsSource Tests

@Suite("PopularHostsSource Tests")
struct PopularHostsSourceTests {

    @Test("All sources have valid URLs")
    func validURLs() {
        for source in PopularHostsSource.allCases {
            #expect(source.url.scheme == "https")
            #expect(source.url.host != nil)
        }
    }

    @Test("All sources have names and descriptions")
    func namesAndDescriptions() {
        for source in PopularHostsSource.allCases {
            #expect(!source.name.isEmpty)
            #expect(!source.description.isEmpty)
            #expect(!source.icon.isEmpty)
        }
    }

    @Test("Steven Black URLs are from GitHub")
    func stevenBlackURLs() {
        #expect(PopularHostsSource.stevenBlackUnified.url.host?.contains("github") == true)
        #expect(PopularHostsSource.stevenBlackFakenews.url.host?.contains("github") == true)
        #expect(PopularHostsSource.stevenBlackGambling.url.host?.contains("github") == true)
    }
}
