import Foundation
@testable import SaneHostsFeature
import XCTest

final class CustomImportIntegrationTests: XCTestCase {
    @MainActor
    func testCustomURLImport() async throws {
        let fixtureText = """
        # Custom Hosts File Test
        127.0.0.1   custom-blocked.com
        0.0.0.0     ad-server.com
        # Comment line
        127.0.0.1   tracker.io  analytics.io
        """

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SaneHosts-ImportTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let fixtureURL = temporaryDirectory.appendingPathComponent("custom-hosts-test")
            .appendingPathExtension("txt")
        try fixtureText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .write(to: fixtureURL, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let service = RemoteSyncService(session: .shared)
        let result = try await service.fetch(from: fixtureURL)

        XCTAssertEqual(result.entries.count, 3, "Should find 3 entries (1 single + 1 single + 1 double-hostname entry)")

        let hostnames = Set(result.entries.flatMap { $0.hostnames })
        XCTAssertTrue(hostnames.contains("custom-blocked.com"))
        XCTAssertTrue(hostnames.contains("ad-server.com"))
        XCTAssertTrue(hostnames.contains("tracker.io"))
        XCTAssertTrue(hostnames.contains("analytics.io"))

        // Test saving to ProfileStore
        let store = ProfileStore(storageRootURL: temporaryDirectory, systemHostsURL: fixtureURL)
        let profileName = "Test Custom Import \(UUID().uuidString)"
        let profile = try await store.createRemote(name: profileName, url: fixtureURL, entries: result.entries)

        let profileURL = temporaryDirectory.appendingPathComponent("Profiles/\(profile.id.uuidString).json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: profileURL.path), "Imported profile must stay in isolated storage")
        XCTAssertEqual(profile.name, profileName)
        XCTAssertEqual(profile.entries.count, 3)
        if case let .remote(sourceUrl, _) = profile.source {
            XCTAssertEqual(sourceUrl, fixtureURL)
        } else {
            XCTFail("Profile source should be remote")
        }

        // Cleanup profile
        try await store.delete(profile: profile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: profileURL.path))
        let backups = try FileManager.default.contentsOfDirectory(
            at: temporaryDirectory.appendingPathComponent("Backups"), includingPropertiesForKeys: nil
        )
        XCTAssertEqual(backups.count, 1, "Deletion backup must stay in isolated storage")
    }

    @MainActor
    func testCustomURLImportRejectsOversizedFiles() async throws {
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let fixtureURL = temporaryDirectory.appendingPathComponent("oversized-hosts-test")
            .appendingPathExtension("txt")
        let oversizedData = Data(count: (25 * 1024 * 1024) + 1)
        try oversizedData.write(to: fixtureURL, options: .atomic)

        defer {
            try? FileManager.default.removeItem(at: fixtureURL)
        }

        let service = RemoteSyncService(session: .shared)

        do {
            _ = try await service.fetch(from: fixtureURL)
            XCTFail("Oversized remote import should be rejected")
        } catch RemoteSyncError.fileTooLarge {
            // Expected.
        } catch {
            XCTFail("Expected fileTooLarge, got \(error)")
        }
    }
}
