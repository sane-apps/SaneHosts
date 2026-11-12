import Foundation
@testable import SaneHostsFeature
import Testing

@Suite("Allowlist")
struct HostAllowlistTests {
    @Test("Pasted URLs and wildcards become bare hostnames")
    func normalizesInput() {
        #expect(HostAllowlist.normalize("https://www.Example.com/path?q=1") == "www.example.com")
        #expect(HostAllowlist.normalize("*.example.com") == "example.com")
        #expect(HostAllowlist.normalize("  example.com.  ") == "example.com")
        #expect(HostAllowlist.normalize("user@shop.example.com:8443") == "shop.example.com")
        #expect(HostAllowlist.normalize("not a site") == nil)
        #expect(HostAllowlist.normalize("") == nil)
        #expect(HostAllowlist.normalize("1.2.3.4") == nil)
    }

    @Test("An allowed domain covers its subdomains but not look-alikes")
    func matchesSubdomains() {
        let allowlist = HostAllowlist(domains: ["example.com"])
        #expect(allowlist.allows("example.com"))
        #expect(allowlist.allows("cdn.example.com"))
        #expect(allowlist.allows("A.B.EXAMPLE.COM"))
        #expect(!allowlist.allows("badexample.com"))
        #expect(!allowlist.allows("example.com.evil.net"))
    }

    @Test("Duplicates and invalid input are rejected; list stays sorted")
    func addRejectsDuplicates() {
        var allowlist = HostAllowlist()
        let addedZeta = allowlist.add("zeta.com")
        let addedAlpha = allowlist.add("alpha.com")
        let addedDuplicate = allowlist.add("https://alpha.com/")
        let addedInvalid = allowlist.add("???")
        #expect(addedZeta)
        #expect(addedAlpha)
        #expect(!addedDuplicate)
        #expect(!addedInvalid)
        #expect(allowlist.domains == ["alpha.com", "zeta.com"])
        allowlist.remove("alpha.com")
        #expect(allowlist.domains == ["zeta.com"])
    }

    @Test("Apply removes allowed hosts from blocking entries only")
    func appliesToBlockingEntriesOnly() {
        let allowlist = HostAllowlist(domains: ["example.com"])
        let entries = [
            HostEntry(ipAddress: "0.0.0.0", hostnames: ["ads.example.com"]),
            HostEntry(ipAddress: "0.0.0.0", hostnames: ["tracker.net", "www.example.com"]),
            HostEntry(ipAddress: "192.168.1.5", hostnames: ["example.com"]),
            HostEntry(ipAddress: "127.0.0.1", hostnames: ["other.org"])
        ]

        let result = allowlist.apply(to: entries)

        #expect(result.count == 3)
        #expect(result[0].hostnames == ["tracker.net"])
        #expect(result[1].ipAddress == "192.168.1.5")
        #expect(result[2].hostnames == ["other.org"])
    }

    @Test("Activation output leaves allowed sites unblocked")
    func mergeHonorsAllowlist() {
        let profile = Profile(name: "Test", entries: [
            HostEntry(ipAddress: "0.0.0.0", hostnames: ["shop.example.com"]),
            HostEntry(ipAddress: "0.0.0.0", hostnames: ["ads.tracker.net"])
        ])
        let content = HostsParser().merge(
            profile: profile,
            systemEntries: [HostEntry(ipAddress: "127.0.0.1", hostnames: ["localhost"])],
            allowlist: HostAllowlist(domains: ["example.com"])
        )

        #expect(!content.contains("shop.example.com"))
        #expect(content.contains("ads.tracker.net"))
        #expect(content.contains("localhost"))
        #expect(throws: Never.self) { try HostsContentValidator.validate(content) }
    }

    @Test("Allowlist store saves and reloads with private permissions")
    @MainActor
    func storeRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("Allowlist.json")

        let store = AllowlistStore(fileURL: fileURL)
        #expect(store.allowlist.isEmpty)
        try store.replace(with: HostAllowlist(domains: ["example.com", "shop.net"]))

        let reloaded = AllowlistStore(fileURL: fileURL)
        #expect(reloaded.allowlist.domains == ["example.com", "shop.net"])
        let permissions = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }
}

@Suite("Blocklist parsing")
struct BlocklistParsingTests {
    @Test("Inline comments never become hostnames")
    func inlineCommentsAreIgnored() {
        let entry = HostsParser().parseBlocklistLine("0.0.0.0 ads.example.com # tracking network")
        #expect(entry?.hostnames == ["ads.example.com"])
        #expect(entry?.comment == nil)
    }

    @Test("Tab-separated lines parse")
    func tabsParse() {
        let entry = HostsParser().parseBlocklistLine("0.0.0.0\tads.example.com")
        #expect(entry?.ipAddress == "0.0.0.0")
        #expect(entry?.hostnames == ["ads.example.com"])
    }

    @Test("Machine names from list headers are skipped")
    func reservedNamesSkipped() {
        let parser = HostsParser()
        let content = """
        127.0.0.1 localhost
        ::1 localhost ip6-localhost ip6-loopback
        ff02::1 ip6-allnodes
        0.0.0.0 0.0.0.0
        # 0.0.0.0 disabled.example.com
        ! adblock comment
        bare-domain.example.com
        0.0.0.0 real.example.com
        """
        let hostnames = parser.parseBlocklist(content).flatMap(\.hostnames)
        #expect(hostnames == ["bare-domain.example.com", "real.example.com"])
    }
}

@Suite("List updates")
struct BlocklistUpdateTests {
    @Test("Refresh keeps entries the user turned off and custom redirects")
    func refreshKeepsUserChoices() {
        let previous = [
            HostEntry(ipAddress: "0.0.0.0", hostnames: ["old.example.com"]),
            HostEntry(ipAddress: "0.0.0.0", hostnames: ["keep-off.example.com"], isEnabled: false),
            HostEntry(ipAddress: "10.0.0.2", hostnames: ["nas.home"]),
            HostEntry(ipAddress: "ff02::1", hostnames: ["ip6-allnodes"], lineNumber: 12),
            HostEntry(ipAddress: "216.34.181.45", hostnames: ["s"], isEnabled: false, lineNumber: 40)
        ]
        let fresh = [
            HostEntry(ipAddress: "0.0.0.0", hostnames: ["keep-off.example.com"]),
            HostEntry(ipAddress: "0.0.0.0", hostnames: ["new.example.com"]),
            HostEntry(ipAddress: "0.0.0.0", hostnames: ["new.example.com"])
        ]

        let merged = BlocklistMerge.refreshed(previous: previous, fresh: fresh)
        let byHost = Dictionary(uniqueKeysWithValues: merged.map { ($0.hostnames[0], $0) })

        #expect(merged.count == 3)
        #expect(byHost["old.example.com"] == nil)
        #expect(byHost["keep-off.example.com"]?.isEnabled == false)
        #expect(byHost["new.example.com"]?.isEnabled == true)
        #expect(byHost["nas.home"]?.ipAddress == "10.0.0.2")
        #expect(byHost["ip6-allnodes"] == nil)
        #expect(byHost["s"] == nil)
    }

    @Test("Signature ignores entry IDs and order")
    func signatureIgnoresIDs() {
        let a = [HostEntry(ipAddress: "0.0.0.0", hostnames: ["a.com"]), HostEntry(ipAddress: "0.0.0.0", hostnames: ["b.com"])]
        let b = [HostEntry(ipAddress: "0.0.0.0", hostnames: ["b.com"]), HostEntry(ipAddress: "0.0.0.0", hostnames: ["a.com"])]
        #expect(BlocklistMerge.signature(of: a) == BlocklistMerge.signature(of: b))
        var c = b
        c[0].isEnabled = false
        #expect(BlocklistMerge.signature(of: a) != BlocklistMerge.signature(of: c))
    }

    @Test("Sources come from the remote URL, saved URLs, or the matching preset")
    @MainActor
    func sourceURLs() throws {
        let url = try #require(URL(string: "https://example.com/hosts"))
        #expect(BlocklistUpdater.sourceURLs(for: Profile(name: "R", source: .remote(url: url, lastFetched: nil))) == [url])
        #expect(BlocklistUpdater.sourceURLs(for: Profile(name: "M", source: .merged(sourceCount: 1), sourceURLs: [url])) == [url])

        let legacyPreset = Profile(name: "Essentials", source: .merged(sourceCount: 3))
        #expect(BlocklistUpdater.sourceURLs(for: legacyPreset) == ProfilePreset.essentials.blocklistSources.map(\.url))
        #expect(!BlocklistUpdater.canUpdate(Profile(name: "Essentials", source: .local)))
        #expect(!BlocklistUpdater.canUpdate(Profile(name: "Mine")))
    }

    @Test("Older profile files without the new keys still load")
    func legacyProfileDecodes() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Old","entries":[],"isActive":false,
         "createdAt":0,"modifiedAt":0,"source":{"local":{}},"colorTag":"blue"}
        """
        let profile = try JSONDecoder().decode(Profile.self, from: Data(json.utf8))
        #expect(profile.sourceURLs == nil)
        #expect(profile.listsUpdatedAt == nil)
        #expect(profile.sortOrder == 0)
    }

    @Test("Updating a file-backed profile reads the file again and saves it")
    @MainActor
    func updateFromFile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let listURL = root.appendingPathComponent("list.txt")
        let systemHosts = root.appendingPathComponent("hosts")
        try "127.0.0.1 localhost\n".write(to: systemHosts, atomically: true, encoding: .utf8)
        try "0.0.0.0 one.example.com\n0.0.0.0 off.example.com\n".write(to: listURL, atomically: true, encoding: .utf8)

        let store = ProfileStore(storageRootURL: root, systemHostsURL: systemHosts)
        let imported = try await RemoteSyncService().fetch(from: listURL)
        var profile = try await store.createRemote(name: "File List", url: listURL, entries: imported.entries)
        try await store.bulkUpdateEntries(ids: Set(profile.entries.filter { $0.hostnames == ["off.example.com"] }.map(\.id)), in: profile) {
            $0.isEnabled = false
        }
        profile = try #require(store.profiles.first { $0.id == profile.id })

        try "0.0.0.0 two.example.com\n0.0.0.0 off.example.com\n".write(to: listURL, atomically: true, encoding: .utf8)
        let result = try await BlocklistUpdater.update(profile, store: store)

        #expect(result.didChange)
        #expect(result.warning == nil)
        let saved = try await store.fullProfile(for: #require(store.profiles.first { $0.id == profile.id }))
        let hosts = Set(saved.entries.flatMap(\.hostnames))
        #expect(hosts == ["two.example.com", "off.example.com"])
        #expect(saved.entries.first { $0.hostnames == ["off.example.com"] }?.isEnabled == false)
        if case let .remote(_, lastFetched) = saved.source {
            #expect(lastFetched != nil)
        } else {
            Issue.record("Source should stay remote")
        }

        let again = try await BlocklistUpdater.update(saved, store: store)
        #expect(!again.didChange)
    }

    @Test("A failed list leaves the profile unchanged")
    @MainActor
    func failedListKeepsProfile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let systemHosts = root.appendingPathComponent("hosts")
        try "127.0.0.1 localhost\n".write(to: systemHosts, atomically: true, encoding: .utf8)
        let missing = root.appendingPathComponent("gone.txt")

        let store = ProfileStore(storageRootURL: root, systemHostsURL: systemHosts)
        let profile = try await store.createRemote(
            name: "Gone",
            url: missing,
            entries: [HostEntry(ipAddress: "0.0.0.0", hostnames: ["kept.example.com"])]
        )

        await #expect(throws: BlocklistUpdateError.self) {
            try await BlocklistUpdater.update(profile, store: store)
        }
        let saved = try #require(store.profiles.first { $0.id == profile.id })
        #expect(saved.entries.map(\.hostnames) == [["kept.example.com"]])
    }

    @Test("Weekly schedule is due after seven days or when never run")
    func weeklySchedule() {
        let now = Date()
        #expect(BlocklistAutoUpdater.isDue(lastCheck: nil, now: now))
        #expect(!BlocklistAutoUpdater.isDue(lastCheck: now.addingTimeInterval(-6 * 86400), now: now))
        #expect(BlocklistAutoUpdater.isDue(lastCheck: now.addingTimeInterval(-7 * 86400), now: now))
    }

    @Test("Auto update defaults on and respects the setting")
    func autoUpdateSetting() throws {
        let defaults = try #require(UserDefaults(suiteName: "sanehosts-test-\(UUID().uuidString)"))
        #expect(BlocklistAutoUpdater.isEnabled(defaults))
        defaults.set(false, forKey: BlocklistAutoUpdater.enabledKey)
        #expect(!BlocklistAutoUpdater.isEnabled(defaults))
    }
}
