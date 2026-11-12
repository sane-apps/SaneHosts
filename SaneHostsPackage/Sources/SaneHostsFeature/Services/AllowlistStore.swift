import Foundation
import OSLog

private let logger = Logger(subsystem: "com.mrsane.SaneHosts", category: "Allowlist")

@MainActor
@Observable
public final class AllowlistStore {
    public static let shared = AllowlistStore(
        fileURL: AllowlistStore.storageDirectory().appendingPathComponent("Allowlist.json")
    )

    public private(set) var allowlist: HostAllowlist

    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
        allowlist = Self.read(from: fileURL)
    }

    nonisolated static func storageDirectory() -> URL {
        if let root = ProfileStore.fixtureStorageRoot() {
            return root
        }
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory unavailable")
        }
        return appSupport.appendingPathComponent("SaneHosts", isDirectory: true)
    }

    public func replace(with newAllowlist: HostAllowlist) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONEncoder().encode(newAllowlist)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        allowlist = newAllowlist
    }

    private static func read(from url: URL) -> HostAllowlist {
        guard let data = try? Data(contentsOf: url) else { return HostAllowlist() }
        do {
            let stored = try JSONDecoder().decode(HostAllowlist.self, from: data)
            return HostAllowlist(domains: stored.domains)
        } catch {
            logger.error("Allowlist file unreadable, starting empty: \(error.localizedDescription)")
            return HostAllowlist()
        }
    }
}
