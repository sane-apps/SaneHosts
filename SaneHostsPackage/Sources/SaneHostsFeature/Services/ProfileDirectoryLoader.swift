import Foundation
import OSLog

private let logger = Logger(subsystem: "com.mrsane.SaneHosts", category: "ProfileStore")

struct LoadResult: Sendable {
    var validProfiles: [Profile]
    var corruptedFiles: [URL]
}

/// Scans the profiles directory, decoding small profiles fully and large ones
/// as identity-checked summaries, then recovers corrupted files from backup or
/// quarantines them.
@MainActor
struct ProfileDirectoryLoader {
    let profilesDirectoryURL: URL
    let backupsDirectoryURL: URL
    let largeProfilePreviewEntryLimit: Int
    let largeProfileSummaryThresholdBytes: Int64
    let archive: ProfileBackupArchive

    private var fileManager: FileManager {
        .default
    }

    /// Returns the loaded profiles, unsorted. Corrupted files are recovered
    /// from backup and re-persisted via `saveRecovered`, or quarantined.
    func load(saveRecovered: @MainActor (Profile) async -> Void) async throws -> [Profile] {
        let profilesDir = profilesDirectoryURL
        let previewLimit = largeProfilePreviewEntryLimit
        let summaryThresholdBytes = largeProfileSummaryThresholdBytes

        // Phase 1: Read and decode valid profiles in background
        let result = try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let files = try fileManager.contentsOfDirectory(at: profilesDir, includingPropertiesForKeys: nil)
            let jsonFiles = files.filter { $0.pathExtension == "json" }

            var validProfiles: [Profile] = []
            var corruptedFiles: [URL] = []

            for file in jsonFiles {
                do {
                    guard let canonicalID = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else {
                        throw ProfileStoreError.invalidProfileIdentity("Profile filename is not a UUID")
                    }

                    // Validate JSON structure before decoding
                    let values = try file.resourceValues(forKeys: [.fileSizeKey])
                    let fileSize = values.fileSize ?? 0
                    let profile: Profile
                    if fileSize > summaryThresholdBytes {
                        profile = try LargeProfileSummaryLoader.loadSummary(
                            from: file,
                            previewEntryLimit: previewLimit
                        )
                    } else {
                        let data = try Data(contentsOf: file)

                        guard !data.isEmpty else {
                            logger.debug(" Empty file detected: \(file.lastPathComponent)")
                            corruptedFiles.append(file)
                            continue
                        }

                        profile = try JSONDecoder().decode(Profile.self, from: data)
                        guard profile.id == canonicalID else {
                            throw ProfileStoreError.invalidProfileIdentity("Stored profile ID does not match its filename")
                        }
                    }

                    // Basic validation: ensure profile has required data
                    guard !profile.name.isEmpty else {
                        logger.debug(" Invalid profile (empty name): \(file.lastPathComponent)")
                        corruptedFiles.append(file)
                        continue
                    }

                    validProfiles.append(profile)
                } catch {
                    logger.debug(" Failed to load \(file.lastPathComponent): \(error.localizedDescription)")
                    corruptedFiles.append(file)
                }
            }
            return LoadResult(validProfiles: validProfiles, corruptedFiles: corruptedFiles)
        }.value

        var loadedProfiles = result.validProfiles
        let corruptedFiles = result.corruptedFiles

        // Phase 2: Handle corrupted files (Main Actor)
        for file in corruptedFiles {
            // Attempt recovery from backup
            let filename = file.deletingPathExtension().lastPathComponent
            if let profileId = UUID(uuidString: filename),
               let recovered = archive.recover(id: profileId) {
                loadedProfiles.append(recovered)
                // Restore the recovered profile to the main directory
                await saveRecovered(recovered)
            } else {
                // Move corrupted files to a quarantine location instead of deleting
                let quarantineName = "CORRUPTED_\(file.lastPathComponent)"
                let quarantineURL = backupsDirectoryURL.appendingPathComponent(quarantineName)
                try? fileManager.moveItem(at: file, to: quarantineURL)
                try? archive.protectPrivateFile(quarantineURL)
                logger.debug(" Quarantined corrupted file: \(quarantineName)")
            }
        }

        return loadedProfiles
    }
}
