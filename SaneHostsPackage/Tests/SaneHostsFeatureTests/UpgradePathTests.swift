import Foundation
@testable import SaneHostsFeature
import Testing

@Suite("Upgrade path")
@MainActor
struct UpgradePathTests {
    @Test("Upgrading from 1.1.26 keeps profiles and starts with safe defaults")
    func upgradeKeepsDataAndDefaults() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let systemHosts = root.appendingPathComponent("hosts")
        try "127.0.0.1 localhost\n".write(to: systemHosts, atomically: true, encoding: .utf8)

        let store = ProfileStore(storageRootURL: root, systemHostsURL: systemHosts)
        let entries = [
            HostEntry(ipAddress: "0.0.0.0", hostnames: ["ads.example.com"]),
            HostEntry(ipAddress: "0.0.0.0", hostnames: ["off.example.com"], isEnabled: false)
        ]
        let created = try await store.createRemote(
            name: "Old List",
            url: #require(URL(string: "https://example.com/hosts.txt")),
            entries: entries
        )
        try await store.markAsActive(profile: created)

        let file = root.appendingPathComponent("Profiles/\(created.id.uuidString).json")
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        json.removeValue(forKey: "sourceURLs")
        json.removeValue(forKey: "listsUpdatedAt")
        try JSONSerialization.data(withJSONObject: json).write(to: file)

        let upgraded = try JSONDecoder().decode(Profile.self, from: Data(contentsOf: file))
        #expect(upgraded.id == created.id)
        #expect(upgraded.name == "Old List")
        #expect(upgraded.isActive)
        #expect(upgraded.entries.count == 2)
        #expect(upgraded.entries.first { $0.hostnames == ["off.example.com"] }?.isEnabled == false)
        #expect(upgraded.listsUpdatedAt == nil)
        if case .remote = upgraded.source {} else {
            Issue.record("Source should stay remote")
        }

        let suite = "sanehosts-upgrade-\(UUID().uuidString)"
        let oldDefaults = try #require(UserDefaults(suiteName: suite))
        defer { oldDefaults.removePersistentDomain(forName: suite) }
        oldDefaults.set(true, forKey: "hasSeenWelcome")
        #expect(BlocklistAutoUpdater.isEnabled(oldDefaults))
        #expect(BlocklistAutoUpdater.lastCheck(oldDefaults) == nil)
        #expect(oldDefaults.object(forKey: ProtectionLock.enabledKey) == nil)
        #expect(!oldDefaults.bool(forKey: ProtectionLock.enabledKey))

        let allowlist = AllowlistStore(fileURL: root.appendingPathComponent("Allowlist.json"))
        #expect(allowlist.allowlist == HostAllowlist())
        #expect(ProtectionController.unlockReason(activating: upgraded, active: nil) == nil)
    }
}
