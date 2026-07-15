import Foundation
@testable import SaneHostsFeature
import Testing

@Suite("Profile Store Large Profile Tests", .serialized)
struct ProfileStoreLargeProfileTests {
    private static let largeProfileID = UUID(uuidString: "17D792BC-843A-4A07-912A-54DE79F2DF22")!
    private static let alternateProfileID = UUID(uuidString: "BDB7C9C8-10EF-4072-AE89-937C68F1EC95")!
    private static let baselineProfileID = UUID(uuidString: "F84F947E-1DD8-4F82-AC87-B9557C68A032")!

    @Test("Large profiles keep filename identity whether entries come before or after ID", arguments: [false, true])
    @MainActor
    func largeProfileIdentityIsStableAcrossReloads(idBeforeEntries: Bool) async throws {
        let fixture = try StorageFixture()
        defer { fixture.remove() }

        let original = Self.largeProfile(id: Self.largeProfileID, name: "Essentials", sortOrder: 0)
        let payload = try Self.encodedProfile(original, idBeforeEntries: idBeforeEntries)
        #expect(payload.count > 2 * 1024 * 1024)
        try fixture.write(payload, profileID: original.id)

        let firstStore = fixture.makeStore()
        await firstStore.load()
        let firstSummary = try #require(firstStore.profiles.first(where: { $0.id == original.id }))
        #expect(firstSummary.hasPartialEntries)
        #expect(firstSummary.entries.first?.id == original.entries.first?.id)
        #expect(firstSummary.id != firstSummary.entries.first?.id)

        let firstHydration = try await firstStore.fullProfile(for: firstSummary)
        #expect(firstHydration.id == original.id)
        #expect(firstHydration.entries.count == original.entries.count)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        let reloadedSummary = try #require(reloadedStore.profiles.first(where: { $0.id == original.id }))
        let reloadedFullProfile = try await reloadedStore.fullProfile(for: reloadedSummary)
        #expect(reloadedSummary.id == original.id)
        #expect(reloadedFullProfile.entries == original.entries)
    }

    @Test("Missing or mismatched top-level identity is quarantined without data loss", arguments: [false, true])
    @MainActor
    func invalidTopLevelIdentityFailsSafely(missingIdentity: Bool) async throws {
        let fixture = try StorageFixture()
        defer { fixture.remove() }

        let baseline = Profile(
            id: Self.baselineProfileID,
            name: "Essentials",
            entries: [Self.entry(at: 90000)],
            createdAt: Self.fixedDate,
            modifiedAt: Self.fixedDate
        )
        try fixture.write(Self.encodedProfile(baseline), profileID: baseline.id)

        let large = Self.largeProfile(id: Self.largeProfileID, name: "Invalid", sortOrder: 1)
        let invalidPayload = try Self.payloadWithInvalidIdentity(
            for: large,
            missingIdentity: missingIdentity
        )
        #expect(invalidPayload.count > 2 * 1024 * 1024)
        try fixture.write(invalidPayload, profileID: large.id)

        let store = fixture.makeStore()
        await store.load()

        #expect(store.profiles.map(\.id) == [baseline.id])
        #expect(!fixture.fileManager.fileExists(atPath: fixture.profileURL(for: large.id).path))
        let quarantinedURL = fixture.backupsURL.appendingPathComponent("CORRUPTED_\(large.id.uuidString).json")
        #expect(try Data(contentsOf: quarantinedURL) == invalidPayload)
    }

    @Test("Hydration rejects identity changes and leaves the backing file untouched", arguments: [false, true])
    @MainActor
    func hydrationValidatesFullPayloadIdentity(missingIdentity: Bool) async throws {
        let fixture = try StorageFixture()
        defer { fixture.remove() }

        let original = Self.largeProfile(id: Self.largeProfileID, name: "Essentials", sortOrder: 0)
        try fixture.write(Self.encodedProfile(original), profileID: original.id)

        let store = fixture.makeStore()
        await store.load()
        let summary = try #require(store.profiles.first(where: { $0.id == original.id }))
        #expect(summary.hasPartialEntries)

        let invalidPayload = try Self.payloadWithInvalidIdentity(
            for: original,
            missingIdentity: missingIdentity
        )
        try invalidPayload.write(to: fixture.profileURL(for: original.id), options: .atomic)

        do {
            _ = try await store.fullProfile(for: summary)
            Issue.record("Hydration accepted a missing or mismatched profile identity")
        } catch {
            #expect(error.localizedDescription.isEmpty == false)
        }
        #expect(try Data(contentsOf: fixture.profileURL(for: original.id)) == invalidPayload)
    }

    @Test("Hydration failures are recorded for diagnostics and cleared by the next success")
    @MainActor
    func hydrationFailureIsRecordedForDiagnostics() async throws {
        let fixture = try StorageFixture()
        defer { fixture.remove() }

        let original = Self.largeProfile(id: Self.largeProfileID, name: "Essentials", sortOrder: 0)
        let validPayload = try Self.encodedProfile(original)
        try fixture.write(validPayload, profileID: original.id)

        let store = fixture.makeStore()
        await store.load()
        let summary = try #require(store.profiles.first(where: { $0.id == original.id }))
        #expect(summary.hasPartialEntries)
        #expect(store.lastHydrationIssue == nil)

        let invalidPayload = try Self.payloadWithInvalidIdentity(for: original, missingIdentity: false)
        try invalidPayload.write(to: fixture.profileURL(for: original.id), options: .atomic)

        do {
            _ = try await store.fullProfile(for: summary)
            Issue.record("Hydration accepted a mismatched profile identity")
        } catch {
            // Expected.
        }
        let issue = try #require(store.lastHydrationIssue)
        #expect(issue.contains("Essentials"))

        try validPayload.write(to: fixture.profileURL(for: original.id), options: .atomic)
        let hydrated = try await store.fullProfile(for: summary)
        #expect(hydrated.entries == original.entries)
        #expect(store.lastHydrationIssue == nil)
    }

    @Test("Reordering hydrates summaries and preserves every large-profile entry")
    @MainActor
    func reorderPreservesFullLargeProfile() async throws {
        let fixture = try StorageFixture()
        defer { fixture.remove() }

        let large = Self.largeProfile(id: Self.largeProfileID, name: "Essentials", sortOrder: 0)
        let other = Profile(
            id: Self.alternateProfileID,
            name: "Other",
            entries: [Self.entry(at: 90001)],
            createdAt: Self.fixedDate,
            modifiedAt: Self.fixedDate,
            sortOrder: 1
        )
        let originalPayload = try Self.encodedProfile(large)
        #expect(originalPayload.count > 2 * 1024 * 1024)
        try fixture.write(originalPayload, profileID: large.id)
        try fixture.write(Self.encodedProfile(other), profileID: other.id)

        let store = fixture.makeStore()
        await store.load()
        let summary = try #require(store.profiles.first(where: { $0.id == large.id }))
        #expect(summary.hasPartialEntries)

        do {
            try await store.save(profile: summary)
            Issue.record("A partial large-profile summary was allowed to overwrite its backing file")
        } catch let error as ProfileStoreError {
            if case .partialProfileRequiresHydration = error {
                // Expected.
            } else {
                Issue.record("Unexpected partial-save error: \(error)")
            }
        }
        #expect(try Data(contentsOf: fixture.profileURL(for: large.id)) == originalPayload)

        try await store.moveProfiles(from: IndexSet(integer: 0), to: 2)

        let persisted = try JSONDecoder().decode(Profile.self, from: Data(contentsOf: fixture.profileURL(for: large.id)))
        #expect(persisted.id == large.id)
        #expect(persisted.sortOrder == 1)
        #expect(persisted.entries == large.entries)

        let reloadedStore = fixture.makeStore()
        await reloadedStore.load()
        let reloadedSummary = try #require(reloadedStore.profiles.first(where: { $0.id == large.id }))
        let reloadedFullProfile = try await reloadedStore.fullProfile(for: reloadedSummary)
        #expect(reloadedFullProfile.entries == large.entries)
    }

    private static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    private static func largeProfile(id: UUID, name: String, sortOrder: Int) -> Profile {
        Profile(
            id: id,
            name: name,
            entries: (0 ..< 15000).map { entry(at: $0) },
            createdAt: fixedDate,
            modifiedAt: fixedDate,
            colorTag: .blue,
            sortOrder: sortOrder
        )
    }

    private static func entry(at index: Int) -> HostEntry {
        let suffix = String(format: "%012llX", Int64(index + 1))
        return HostEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!,
            ipAddress: "0.0.0.0",
            hostnames: ["entry-\(index).example.test"],
            comment: String(repeating: "x", count: 64),
            isEnabled: index.isMultiple(of: 10) == false,
            lineNumber: index + 1
        )
    }

    private static func encodedProfile(_ profile: Profile, idBeforeEntries: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(profile)
        guard idBeforeEntries else { return encoded }

        let idValue = try #require(String(data: encoder.encode(profile.id), encoding: .utf8))
        let json = try #require(String(data: encoded, encoding: .utf8))
        let idMember = ",\"id\":\(idValue)"
        let jsonWithoutID = json.replacingOccurrences(of: idMember, with: "")
        #expect(jsonWithoutID != json)
        return Data("{\"id\":\(idValue),\(jsonWithoutID.dropFirst())".utf8)
    }

    private static func payloadWithInvalidIdentity(for profile: Profile, missingIdentity: Bool) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(profile)
        let json = try #require(String(data: encoded, encoding: .utf8))
        let profileIDValue = try #require(String(data: encoder.encode(profile.id), encoding: .utf8))
        let idMember = ",\"id\":\(profileIDValue)"
        let replacement: String
        if missingIdentity {
            replacement = ""
        } else {
            let alternateIDValue = try #require(String(data: encoder.encode(alternateProfileID), encoding: .utf8))
            replacement = ",\"id\":\(alternateIDValue)"
        }
        let invalidJSON = json.replacingOccurrences(of: idMember, with: replacement)
        #expect(invalidJSON != json)
        return Data(invalidJSON.utf8)
    }
}

private struct StorageFixture {
    let fileManager = FileManager.default
    let rootURL: URL
    let profilesURL: URL
    let backupsURL: URL
    let systemHostsURL: URL

    init() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SaneHosts-ProfileStoreTests-\(UUID().uuidString)", isDirectory: true)
        rootURL = root
        profilesURL = root.appendingPathComponent("Profiles", isDirectory: true)
        backupsURL = root.appendingPathComponent("Backups", isDirectory: true)
        systemHostsURL = root.appendingPathComponent("hosts")
        try FileManager.default.createDirectory(at: profilesURL, withIntermediateDirectories: true)
        try "127.0.0.1 localhost\n::1 localhost\n".write(to: systemHostsURL, atomically: true, encoding: .utf8)
    }

    @MainActor
    func makeStore() -> ProfileStore {
        ProfileStore(storageRootURL: rootURL, systemHostsURL: systemHostsURL)
    }

    func profileURL(for id: UUID) -> URL {
        profilesURL.appendingPathComponent("\(id.uuidString).json")
    }

    func write(_ data: Data, profileID: UUID) throws {
        try data.write(to: profileURL(for: profileID), options: .atomic)
    }

    func remove() {
        try? fileManager.removeItem(at: rootURL)
    }
}
