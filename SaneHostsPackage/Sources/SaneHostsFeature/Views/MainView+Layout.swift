import AppKit
import SaneUI
import SwiftUI
import UniformTypeIdentifiers

extension MainView {
    // MARK: - Selection Actions

    func selectAllProfiles() {
        selectedProfileIDs = Set(store.profiles.map(\.id))
    }

    func deselectAllProfiles() {
        if let first = store.profiles.first {
            selectedProfileIDs = [first.id]
        } else {
            selectedProfileIDs = []
        }
    }

    // MARK: - Sidebar

    var sidebar: some View {
        List(selection: $selectedProfileIDs) {
            if let title = MainViewGatePolicy.trialCountdownTitle(daysRemaining: licenseService.proTrialDaysRemaining) {
                Section {
                    TrialCountdownCard(title: title) {
                        if let url = licenseService.checkoutURL {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }

            // Golden-ratio oriented sidebar: immediate free path first.
            Section {
                // Primary free path: one-click protection with Essentials selected by default.
                if let primaryProfile = selectedProfile ?? store.profiles.first {
                    QuickActionButton(
                        title: primaryProfile.isActive ? "Disable Protection" : "Enable Protection",
                        subtitle: primaryProfile.isActive ? "Restore original hosts file" : "Apply \(primaryProfile.name) in one click",
                        icon: primaryProfile.isActive ? "shield.slash.fill" : "shield.checkered",
                        color: primaryProfile.isActive ? .orange : .green
                    ) {
                        if primaryProfile.isActive {
                            deactivateProfile()
                        } else {
                            activateProfile(primaryProfile)
                        }
                    }
                }

                QuickActionButton(
                    title: "Open Essentials",
                    subtitle: "Review and edit your free profile",
                    icon: "list.bullet.rectangle",
                    color: .blue
                ) {
                    if let essentials = store.profiles.first(where: { $0.name.caseInsensitiveCompare("Essentials") == .orderedSame })
                        ?? store.profiles.first {
                        selectedProfileIDs = [essentials.id]
                        selectedPreset = nil
                    }
                }
            } header: {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("QUICK ACTIONS")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(.white)
            }

            Section {
                // Pro action: import curated blocklists.
                QuickActionButton(
                    title: "Import Blocklist",
                    subtitle: "Block ads and trackers",
                    icon: "arrow.down.circle.fill",
                    color: .blue,
                    isPro: licenseService.isPro
                ) {
                    if licenseService.isPro {
                        showingRemoteImport = true
                    } else {
                        proUpsellFeature = .importProfiles
                    }
                }

                // Create custom profile (always visible, Pro gated).
                QuickActionButton(
                    title: "New Empty Profile",
                    subtitle: "Create a custom profile",
                    icon: "plus.circle.fill",
                    color: .orange,
                    isPro: licenseService.isPro
                ) {
                    if licenseService.isPro {
                        showingNewProfile = true
                    } else {
                        proUpsellFeature = .multipleProfiles
                    }
                }

                // Start from a built-in template (always visible, Pro gated).
                QuickActionButton(
                    title: "From Template",
                    subtitle: "Start with a preset",
                    icon: "doc.badge.plus",
                    color: .purple,
                    isPro: licenseService.isPro
                ) {
                    if licenseService.isPro {
                        showingTemplates = true
                    } else {
                        proUpsellFeature = .downloadablePresets
                    }
                }

                // Merge is always visible; execution requires 2+ profiles.
                let canMerge = store.profiles.count >= 2
                QuickActionButton(
                    title: "Merge Profiles",
                    subtitle: canMerge ? "Combine profiles" : "Need 2+ profiles",
                    icon: "arrow.triangle.merge",
                    color: .pink,
                    isPro: licenseService.isPro
                ) {
                    if !licenseService.isPro {
                        proUpsellFeature = .profileMerge
                        return
                    }
                    guard canMerge else {
                        activationWarning = "Create or import a second profile before merging."
                        return
                    }
                    showingMergeProfiles = true
                }
            } header: {
                HStack(spacing: 6) {
                    Image(systemName: ProFeature.sectionIcon(isPro: licenseService.isPro))
                        .font(.system(size: 13, weight: .semibold))
                    Text("PRO FEATURES")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(.white)
            }

            Section {
                ForEach(Array(store.profiles.enumerated()), id: \.element.id) { index, profile in
                    ProfileRowView(profile: profile)
                        .tag(profile.id)
                        .essentialsProfileAnchor(enabled: index == 0)
                        .accessibilityLabel("\(profile.name), \(profile.isActive ? "active" : "inactive"), \(profile.entryCount) entries")
                        .contextMenu {
                            profileContextMenu(for: profile)
                        }
                }
                .onMove { source, destination in
                    Task {
                        try? await store.moveProfiles(from: source, to: destination)
                    }
                }
            } header: {
                HStack(spacing: 6) {
                    Image(systemName: SaneIcons.profiles)
                        .font(.system(size: 13, weight: .semibold))
                    Text("PROFILES")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(.white)
            }

            // Protection Levels - presets not yet downloaded (Pro feature)
            if !availablePresets.isEmpty {
                Section {
                    ForEach(availablePresets) { preset in
                        PresetRowView(
                            preset: preset,
                            isSelected: selectedPreset == preset,
                            showLock: !licenseService.isPro,
                            onLockedTap: {
                                showPresetUpsell(for: preset)
                            }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if licenseService.isPro {
                                selectedProfileIDs = []
                                selectedPreset = preset
                            } else {
                                showPresetUpsell(for: preset)
                            }
                        }
                        .accessibilityLabel("\(preset.displayName) protection level")
                        .accessibilityHint(licenseService.isPro ? "Double-tap to view details and download" : "Pro feature — double-tap to upgrade")
                    }
                } header: {
                    HStack(spacing: 6) {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 13, weight: .semibold))
                        Text("PROTECTION LEVELS")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("SaneHosts")
        .sheet(isPresented: $showingNewProfile) {
            NewProfileSheet(store: store) { profile in
                selectedProfileIDs = [profile.id]
            }
        }
        .sheet(isPresented: $showingTemplates) {
            TemplatePickerSheet(store: store) { profile in
                selectedProfileIDs = [profile.id]
            }
        }
        .sheet(isPresented: $showingRemoteImport) {
            RemoteImportSheet(store: store) { profile in
                selectedProfileIDs = [profile.id]
            }
        }
        .sheet(isPresented: $showingMergeProfiles) {
            MergeProfilesSheet(store: store, preselectedIDs: selectedProfileIDs) { profile in
                selectedProfileIDs = [profile.id]
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    var detail: some View {
        if let preset = selectedPreset {
            // Preset selected - show info and download
            PresetDetailView(
                preset: preset,
                isDownloading: isDownloadingPreset
            ) {
                downloadPreset(preset)
            }
        } else if selectedProfileIDs.count > 1 {
            // Multiple selection - show batch actions
            MultiSelectDetailView(
                profiles: selectedProfiles,
                onMerge: {
                    if licenseService.isPro {
                        showingMergeProfiles = true
                    } else {
                        proUpsellFeature = .profileMerge
                    }
                },
                onExport: { exportSelectedProfiles() },
                onDelete: { deleteWithConfirmation() }
            )
        } else if let profile = selectedProfile {
            // Single selection - show detail
            ProfileDetailView(
                profile: profile,
                store: store,
                onActivate: { activateProfile(profile) },
                onDeactivate: { deactivateProfile() },
                licenseService: licenseService
            )
        } else {
            // No selection
            SaneEmptyState(
                icon: SaneIcons.hosts,
                title: "No Profile Selected",
                description: "Select a profile or choose a protection level to get started.",
                actionTitle: "Open Essentials"
            ) {
                if let essentials = store.profiles.first(where: { $0.name.caseInsensitiveCompare("Essentials") == .orderedSame })
                    ?? store.profiles.first {
                    selectedProfileIDs = [essentials.id]
                    selectedPreset = nil
                }
            }
            .accessibilityLabel("No profile selected. Select a profile or choose a protection level to get started.")
        }
    }
}
