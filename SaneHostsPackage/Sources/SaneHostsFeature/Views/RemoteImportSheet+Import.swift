import AppKit
import SaneUI
import SwiftUI
import UniformTypeIdentifiers

extension RemoteImportSheet {
    // MARK: - Footer

    var footer: some View {
        VStack(spacing: 14) {
            // Profile name (shown when selections made)
            if !selectedSources.isEmpty || !customURL.isEmpty {
                HStack {
                    Text("Profile Name:")
                        .font(.body)
                        .foregroundColor(.white)
                    TextField(suggestedName, text: $profileName)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .padding(10)
                        .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white)
                        .cornerRadius(8)
                }
            }

            // Selection summary
            HStack {
                if selectedSources.isEmpty, customURL.isEmpty {
                    Text("Select blocklists to import")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                } else if selectedSources.count == 1 {
                    Text("1 blocklist selected")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                } else if selectedSources.count > 1 {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.merge")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.indigo)
                        Text("\(selectedSources.count) blocklists will be merged")
                            .font(.system(size: 13, weight: .semibold))
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    }
                } else if !customURL.isEmpty {
                    Text("Custom URL ready to import")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                }

                Spacer()

                // Error display
                if let error {
                    Text(error)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(2)
                }

                // Buttons
                Button("Cancel") {
                    cancelImport()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(SaneActionButtonStyle())

                Button(importButtonTitle) {
                    startImport()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(SaneActionButtonStyle(prominent: true))
                .disabled(selectedSources.isEmpty && customURL.isEmpty)
            }
        }
    }

    var importButtonTitle: String {
        if selectedSources.count > 1 {
            "Import & Merge"
        } else {
            "Import"
        }
    }

    var suggestedName: String {
        if selectedSources.count == 1 {
            let sourceId = selectedSources.first ?? ""
            return BlocklistCatalog.all.first { $0.id == sourceId }?.name ?? "Blocklist"
        } else if selectedSources.count > 1 {
            // Generate descriptive name from selected sources
            let sources = BlocklistCatalog.all.filter { selectedSources.contains($0.id) }
            return generateCombinedName(from: sources)
        } else if !customURL.isEmpty {
            return URL(string: customURL)?.host ?? "Custom"
        }
        return "Blocklist"
    }

    func generateCombinedName(from sources: [BlocklistSource]) -> String {
        guard !sources.isEmpty else { return "Combined Blocklist" }

        // If 2-3 sources, combine their names
        if sources.count <= 3 {
            let names = sources.map { shortenSourceName($0.name) }
            return names.joined(separator: " + ")
        }

        // For 4+ sources, use first name + count
        let firstName = shortenSourceName(sources[0].name)
        return "\(firstName) + \(sources.count - 1) more"
    }

    func shortenSourceName(_ name: String) -> String {
        var shortened = name
        // Remove common words to keep names concise
        let removables = ["Steven Black ", " Unified", " Basic", " Default", " Block", " List", " Filter"]
        for removable in removables {
            shortened = shortened.replacingOccurrences(of: removable, with: "")
        }
        return shortened.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Import Progress Overlay

    var importProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView(value: importProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)
                    .tint(.blue)

                Text(currentImportName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)

                if selectedSources.count > 1 {
                    Text("Importing \(Int(importProgress * Double(selectedSources.count))) of \(selectedSources.count)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                }

                Button("Cancel") {
                    cancelImport()
                }
                .buttonStyle(SaneActionButtonStyle())
                .accessibilityLabel("Cancel import")
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )
        }
    }

    // MARK: - Import Logic

    func startImport() {
        let finalName = profileName.isEmpty ? suggestedName : profileName
        importTask?.cancel()
        isImporting = true
        importProgress = 0
        error = nil

        importTask = Task { @MainActor in
            defer {
                isImporting = false
                importTask = nil
            }

            do {
                // Handle custom URL
                if !customURL.isEmpty, let url = URL(string: customURL) {
                    currentImportName = "Downloading \(url.host ?? "custom")..."
                    let remoteFile = try await RemoteSyncService.shared.fetch(from: url)
                    let profile = try await store.createRemote(name: finalName, url: url, entries: remoteFile.entries)
                    onCreated(profile)
                    dismiss()
                    return
                }

                // Handle catalog selections
                let sources = BlocklistCatalog.all.filter { selectedSources.contains($0.id) }
                var allEntries: [HostEntry] = []
                var seenHostnames: Set<String> = []
                let maxImportedEntries = 500_000

                for (index, source) in sources.enumerated() {
                    try Task.checkCancellation()
                    guard allEntries.count < maxImportedEntries else { break }
                    currentImportName = "Downloading \(source.name)..."
                    importProgress = Double(index) / Double(sources.count)

                    let remoteFile = try await RemoteSyncService.shared.fetch(from: source.url)

                    // Deduplicate as we go
                    for entry in remoteFile.entries {
                        guard allEntries.count < maxImportedEntries else { break }
                        let key = entry.hostnames.sorted().joined(separator: ",")
                        if !seenHostnames.contains(key) {
                            seenHostnames.insert(key)
                            allEntries.append(entry)
                        }
                    }
                }

                importProgress = 1.0
                currentImportName = "Saving profile..."

                // Create the profile
                let profile: Profile = if sources.count == 1 {
                    // Single source - create as remote
                    try await store.createRemote(
                        name: finalName,
                        url: sources[0].url,
                        entries: allEntries
                    )
                } else {
                    // Multiple sources - create as merged
                    try await store.createMerged(
                        name: finalName,
                        entries: allEntries,
                        sourceCount: sources.count
                    )
                }

                onCreated(profile)
                dismiss()

            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func cancelImport() {
        importTask?.cancel()
        importTask = nil
        RemoteSyncService.shared.cancel()
        isImporting = false
        currentImportName = ""
    }
}
