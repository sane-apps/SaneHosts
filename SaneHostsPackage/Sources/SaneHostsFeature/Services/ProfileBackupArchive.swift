import Foundation
import OSLog

private let logger = Logger(subsystem: "com.mrsane.SaneHosts", category: "ProfileStore")

/// Owns profile backup snapshots, corrupted-profile recovery from backup, and
/// the private (0600/0700) permissions on everything under the storage root.
struct ProfileBackupArchive {
    let profilesDirectoryURL: URL
    let backupsDirectoryURL: URL
    let maxBackupsPerProfile: Int

    private var fileManager: FileManager {
        .default
    }

    /// Create a backup of a profile before destructive operations
    func backup(_ profile: Profile) {
        let sourceURL = profilesDirectoryURL.appendingPathComponent("\(profile.id.uuidString).json")
        guard fileManager.fileExists(atPath: sourceURL.path) else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupName = "\(profile.id.uuidString)_\(timestamp).json"
        let backupURL = backupsDirectoryURL.appendingPathComponent(backupName)

        do {
            try fileManager.copyItem(at: sourceURL, to: backupURL)
            try protectPrivateFile(backupURL)
            cleanupOldBackups(for: profile.id)
            logger.debug(" Backup created: \(backupName)")
        } catch {
            logger.debug(" Backup failed: \(error.localizedDescription)")
        }
    }

    /// Remove old backups keeping only the most recent ones
    private func cleanupOldBackups(for profileId: UUID) {
        do {
            let files = try fileManager.contentsOfDirectory(at: backupsDirectoryURL, includingPropertiesForKeys: [.creationDateKey])
            let profileBackups = files
                .filter { $0.lastPathComponent.hasPrefix(profileId.uuidString) }
                .sorted { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                    return date1 > date2
                }

            // Delete backups beyond the limit
            for backup in profileBackups.dropFirst(maxBackupsPerProfile) {
                try? fileManager.removeItem(at: backup)
            }
        } catch {
            logger.debug(" Cleanup failed: \(error.localizedDescription)")
        }
    }

    /// Attempt to recover a corrupted profile from backup
    func recover(id: UUID) -> Profile? {
        do {
            let files = try fileManager.contentsOfDirectory(at: backupsDirectoryURL, includingPropertiesForKeys: [.creationDateKey])
            let backups = files
                .filter { $0.lastPathComponent.hasPrefix(id.uuidString) }
                .sorted { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                    return date1 > date2
                }

            for backup in backups {
                do {
                    let data = try Data(contentsOf: backup)
                    let profile = try JSONDecoder().decode(Profile.self, from: data)
                    guard profile.id == id else {
                        logger.debug(" Ignoring backup with mismatched profile identity: \(backup.lastPathComponent)")
                        continue
                    }
                    logger.debug(" Recovered profile from backup: \(backup.lastPathComponent)")
                    return profile
                } catch {
                    continue // Try next backup
                }
            }
        } catch {
            logger.debug(" Recovery scan failed: \(error.localizedDescription)")
        }
        return nil
    }

    func protectStoragePermissions() throws {
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: profilesDirectoryURL.path)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: backupsDirectoryURL.path)

        for directory in [profilesDirectoryURL, backupsDirectoryURL] {
            let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "json" {
                try? protectPrivateFile(file)
            }
        }
    }

    func protectPrivateFile(_ url: URL) throws {
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
