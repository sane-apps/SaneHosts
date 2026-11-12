import AppKit
import SaneUI
import SwiftUI
import UniformTypeIdentifiers

extension MainView {
    // MARK: - Preset Download

    func downloadPreset(_ preset: ProfilePreset) {
        guard !isDownloadingPreset else { return }
        guard licenseService.isPro else {
            proUpsellFeature = .downloadablePresets
            return
        }
        isDownloadingPreset = true

        Task {
            do {
                try await store.createProfile(from: preset)
                if let newProfile = store.profiles.first(where: { $0.name == preset.displayName }) {
                    selectedProfileIDs = [newProfile.id]
                    selectedPreset = nil
                }
            } catch {
                activationError = "Failed to download \(preset.displayName): \(error.localizedDescription)"
            }
            isDownloadingPreset = false
        }
    }

    func showPresetUpsell(for preset: ProfilePreset) {
        activationWarning = "\(preset.displayName): \(preset.tagline)"
        proUpsellFeature = .downloadablePresets
    }

    // MARK: - Context Menu

    @ViewBuilder
    func profileContextMenu(for profile: Profile) -> some View {
        if profile.isActive {
            Button {
                deactivateProfile()
            } label: {
                Label(ProtectionUXCopy.turnOffActionTitle, systemImage: SaneIcons.deactivate)
            }
        } else {
            Button {
                activateProfile(profile)
            } label: {
                Label("Activate", systemImage: SaneIcons.activate)
            }
        }

        Divider()

        Button {
            if licenseService.isPro {
                Task {
                    if let newProfile = try? await store.duplicate(profile: profile) {
                        selectedProfileIDs = [newProfile.id]
                    }
                }
            } else {
                proUpsellFeature = .duplicateProfile
            }
        } label: {
            Label(
                licenseService.isPro ? "Duplicate" : "Duplicate (Locked)",
                systemImage: licenseService.isPro ? SaneIcons.duplicate : "lock.fill"
            )
        }

        Button {
            exportProfile(profile)
        } label: {
            Label("Export...", systemImage: SaneIcons.export)
        }

        Divider()

        Button(role: .destructive) {
            if selectedProfileIDs.count > 1, selectedProfileIDs.contains(profile.id) {
                deleteWithConfirmation()
            } else {
                selectedProfileIDs = [profile.id]
                deleteWithConfirmation()
            }
        } label: {
            if selectedProfileIDs.count > 1, selectedProfileIDs.contains(profile.id) {
                Label("Delete \(selectedProfileIDs.count) Profiles", systemImage: SaneIcons.remove)
            } else {
                Label("Delete", systemImage: SaneIcons.remove)
            }
        }
        .disabled(profile.isActive)
    }

    // MARK: - Single Profile Actions

    func activateProfile(_ profile: Profile) {
        guard !isActivating else { return }
        isActivating = true
        activationError = nil
        activationWarning = nil
        Task {
            defer { isActivating = false }
            do {
                if let warning = try await ProtectionController.activate(profile) {
                    activationWarning = warning
                } else {
                    withAnimation { showingActivationSuccess = true }
                }
            } catch {
                activationError = HostsServiceError.actionErrorMessage(
                    for: error,
                    action: "Couldn’t activate \(profile.name)"
                )
            }
        }
    }

    func deactivateProfile() {
        guard !isActivating else { return }
        isActivating = true
        activationError = nil
        activationWarning = nil
        Task {
            defer { isActivating = false }
            do {
                activationWarning = try await ProtectionController.deactivate()
            } catch {
                activationError = HostsServiceError.actionErrorMessage(
                    for: error,
                    action: "Couldn’t turn off protection"
                )
            }
        }
    }

    /// Saves the allowlist and, when protection is on, writes it to the hosts file.
    func saveAllowlist(_ allowlist: HostAllowlist) {
        do {
            try AllowlistStore.shared.replace(with: allowlist)
        } catch {
            activationError = "Couldn’t save allowed sites: \(error.localizedDescription)"
            return
        }
        guard store.activeProfile != nil, !isActivating else { return }
        isActivating = true
        Task {
            defer { isActivating = false }
            do {
                activationWarning = try await ProtectionController.reapplyActiveProfile()
            } catch {
                activationError = HostsServiceError.actionErrorMessage(
                    for: error,
                    action: "Allowed sites were saved, but couldn’t be applied"
                )
            }
        }
    }

    func exportProfile(_ profile: Profile) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(profile.name).hosts"

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                do {
                    let fullProfile = try await store.fullProfile(for: profile)
                    let content = store.exportProfile(fullProfile)
                    try content.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    activationError = "Failed to export \(profile.name): \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Multi-Select Actions

    func deleteWithConfirmation() {
        guard !selectedProfileIDs.isEmpty else { return }
        let deletableCount = selectedProfiles.filter { !$0.isActive }.count
        if deletableCount == 0 {
            activationError = "Cannot delete active profiles. Turn off protection first."
            return
        }
        showingDeleteConfirmation = true
    }

    func deleteSelectedProfiles() {
        let idsToDelete = selectedProfiles.filter { !$0.isActive }.map(\.id)
        guard !idsToDelete.isEmpty else { return }

        selectedProfileIDs = []
        store.deleteProfiles(ids: idsToDelete)

        if let first = store.profiles.first {
            selectedProfileIDs = [first.id]
        }
    }

    func duplicateSelectedProfiles() {
        guard licenseService.isPro else {
            proUpsellFeature = .duplicateProfile
            return
        }
        Task {
            var newIDs: [UUID] = []
            for profile in selectedProfiles {
                if let newProfile = try? await store.duplicate(profile: profile) {
                    newIDs.append(newProfile.id)
                }
            }
            if !newIDs.isEmpty {
                selectedProfileIDs = Set(newIDs)
            }
        }
    }

    func exportSelectedProfiles() {
        if selectedProfiles.count == 1, let profile = selectedProfiles.first {
            exportProfile(profile)
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose folder to export \(selectedProfiles.count) profiles"

        if panel.runModal() == .OK, let folderURL = panel.url {
            let profilesToExport = selectedProfiles
            Task {
                do {
                    for profile in profilesToExport {
                        let fullProfile = try await store.fullProfile(for: profile)
                        let content = store.exportProfile(fullProfile)
                        let fileURL = folderURL.appendingPathComponent("\(profile.name).hosts")
                        try content.write(to: fileURL, atomically: true, encoding: .utf8)
                    }
                } catch {
                    activationError = "Failed to export profiles: \(error.localizedDescription)"
                }
            }
        }
    }

    func activateFirstSelected() {
        guard let profile = selectedProfiles.first else { return }
        activateProfile(profile)
    }
}
