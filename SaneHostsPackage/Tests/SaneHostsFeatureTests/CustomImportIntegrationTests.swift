import XCTest
@testable import SaneHostsFeature
import Foundation

final class CustomImportIntegrationTests: XCTestCase {
    
    var serverProcess: Process!
    let port = 8999
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("sanehosts_test_data")
    
    override func setUp() async throws {
        // Create temp dir and hosts file
        try? FileManager.default.removeItem(at: tempDir)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let hostsContent = """
        # Custom Hosts File Test
        127.0.0.1   custom-blocked.com
        0.0.0.0     ad-server.com
        # Comment line
        127.0.0.1   tracker.io  analytics.io
        """
        
        try hostsContent.write(to: tempDir.appendingPathComponent("hosts"), atomically: true, encoding: .utf8)
        
        // Start Python HTTP Server
        serverProcess = Process()
        serverProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        serverProcess.arguments = ["python3", "-m", "http.server", String(port), "--bind", "127.0.0.1", "--directory", tempDir.path]
        
        try serverProcess.run()
        
        // Wait for server to start
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
    }
    
    override func tearDown() async throws {
        serverProcess.terminate()
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    @MainActor
    func testCustomURLImport() async throws {
        let url = URL(string: "http://127.0.0.1:\(port)/hosts")!
        let service = RemoteSyncService()
        
        // Test fetching
        let result = try await service.fetch(from: url)
        
        XCTAssertEqual(result.entries.count, 3, "Should find 3 entries (1 single + 1 single + 1 double-hostname entry)")
        
        let hostnames = Set(result.entries.flatMap { $0.hostnames })
        XCTAssertTrue(hostnames.contains("custom-blocked.com"))
        XCTAssertTrue(hostnames.contains("ad-server.com"))
        XCTAssertTrue(hostnames.contains("tracker.io"))
        XCTAssertTrue(hostnames.contains("analytics.io"))
        
        // Test saving to ProfileStore
        let store = ProfileStore() // New instance for test
        // Use a unique name to avoid conflicts if store persists to disk in test env
        let profileName = "Test Custom Import \(UUID().uuidString)"
        
        let profile = try await store.createRemote(name: profileName, url: url, entries: result.entries)
        
        XCTAssertEqual(profile.name, profileName)
        XCTAssertEqual(profile.entries.count, 3)
        if case .remote(let sourceUrl, _) = profile.source {
            XCTAssertEqual(sourceUrl, url)
        } else {
            XCTFail("Profile source should be remote")
        }
        
        // Cleanup profile
        try await store.delete(profile: profile)
    }
}
