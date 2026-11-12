import Foundation
@testable import SaneHostsFeature
import Testing

@MainActor
private final class PromptLog {
    var reasons: [String] = []
}

@Suite("Protection lock", .serialized)
@MainActor
struct ProtectionLockTests {
    /// Runs `body` with private preferences and a scripted authenticator.
    private func withLock(
        enabled: Bool,
        authAnswer: Bool,
        _ body: (_ log: PromptLog) async throws -> Void
    ) async throws {
        let suite = "sanehosts-lock-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(enabled, forKey: ProtectionLock.enabledKey)

        let log = PromptLog()
        let savedDefaults = ProtectionLock.defaults
        let savedAuth = ProtectionLock.authenticate
        let savedNow = ProtectionLock.now
        ProtectionLock.lastUnlock = nil
        ProtectionLock.defaults = defaults
        ProtectionLock.authenticate = { reason in
            log.reasons.append(reason)
            return authAnswer
        }
        defer {
            ProtectionLock.defaults = savedDefaults
            ProtectionLock.authenticate = savedAuth
            ProtectionLock.now = savedNow
            ProtectionLock.lastUnlock = nil
        }
        try await body(log)
    }

    @Test("Lock off: no prompt, always allowed")
    func lockOffNeverPrompts() async throws {
        try await withLock(enabled: false, authAnswer: false) { log in
            let allowed = await ProtectionLock.authorize("turn off protection")
            #expect(allowed)
            #expect(log.reasons.isEmpty)
        }
    }

    @Test("Lock on: the prompt's answer decides")
    func lockOnUsesPrompt() async throws {
        try await withLock(enabled: true, authAnswer: false) { log in
            let allowed = await ProtectionLock.authorize("turn off protection")
            #expect(!allowed)
            #expect(log.reasons == ["turn off protection"])
        }
        try await withLock(enabled: true, authAnswer: true) { _ in
            let allowed = await ProtectionLock.authorize("switch protection to Essentials")
            #expect(allowed)
        }
    }

    @Test("One unlock covers the next two minutes, then it asks again")
    func graceWindow() async throws {
        try await withLock(enabled: true, authAnswer: true) { log in
            var clock = Date(timeIntervalSince1970: 1_000_000)
            ProtectionLock.now = { clock }
            #expect(await ProtectionLock.authorize("turn off protection"))
            clock += 119
            #expect(await ProtectionLock.authorize("change Allowed Sites"))
            #expect(log.reasons == ["turn off protection"])
            clock += 2
            #expect(await ProtectionLock.authorize("change Allowed Sites"))
            #expect(log.reasons == ["turn off protection", "change Allowed Sites"])
        }
    }

    @Test("Turning the lock off needs authentication; turning it on does not")
    func turningOffNeedsAuth() async throws {
        try await withLock(enabled: true, authAnswer: false) { log in
            let changed = await ProtectionLock.setEnabled(false)
            #expect(!changed)
            #expect(ProtectionLock.isEnabled)
            #expect(log.reasons == ["turn off the protection lock"])
        }
        try await withLock(enabled: false, authAnswer: false) { log in
            let changed = await ProtectionLock.setEnabled(true)
            #expect(changed)
            #expect(ProtectionLock.isEnabled)
            #expect(log.reasons.isEmpty)
        }
    }

    @Test("Editing the active profile asks first; other profiles do not")
    func activeProfileEditsAreLocked() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let systemHosts = root.appendingPathComponent("hosts")
        try "127.0.0.1 localhost\n".write(to: systemHosts, atomically: true, encoding: .utf8)
        let store = ProfileStore(storageRootURL: root, systemHostsURL: systemHosts)
        let entry = HostEntry(ipAddress: "0.0.0.0", hostnames: ["ads.example.com"])
        let active = try await store.createRemote(name: "Active", url: URL(string: "https://example.com/a.txt")!, entries: [entry])
        let other = try await store.createRemote(name: "Other", url: URL(string: "https://example.com/b.txt")!, entries: [entry])
        try await store.markAsActive(profile: active)

        try await withLock(enabled: true, authAnswer: false) { log in
            let current = try #require(store.profiles.first { $0.id == active.id })
            await #expect(throws: HostsServiceError.self) {
                try await store.toggleEntry(entry, in: current)
            }
            let saved = try await store.fullProfile(for: current)
            let allStillOn = saved.entries.allSatisfy { $0.isEnabled }
            #expect(allStillOn)
            #expect(log.reasons == ["change the active profile"])

            let otherNow = try #require(store.profiles.first { $0.id == other.id })
            try await store.toggleEntry(entry, in: otherNow)
            #expect(log.reasons.count == 1)
        }
    }

    @Test("Turning protection on from off never asks; switching away does")
    func onlySwitchingAsks() {
        let a = Profile(name: "Essentials")
        let b = Profile(name: "Kitchen Sink")
        #expect(ProtectionController.unlockReason(activating: a, active: nil) == nil)
        #expect(ProtectionController.unlockReason(activating: a, active: a) == nil)
        #expect(ProtectionController.unlockReason(activating: b, active: a) == "switch protection to Kitchen Sink")
    }

    @Test("A cancelled prompt stops Turn Off Protection before anything is written")
    func cancelledPromptStopsDeactivate() async throws {
        try await withLock(enabled: true, authAnswer: false) { log in
            await #expect(throws: HostsServiceError.self) {
                try await ProtectionController.deactivate()
            }
            #expect(log.reasons == ["turn off protection"])
            #expect(!HostsService.shared.isWriting)
        }
    }
}
