import AppKit
import SaneUI
import SwiftUI
import UniformTypeIdentifiers

enum MainViewGatePolicy {
    static func canOpenRemoteImport(isPro: Bool) -> Bool {
        isPro
    }

    static func allowsBasicAfterTrial(hasExpiredProTrial: Bool) -> Bool {
        false
    }

    static func trialCountdownTitle(daysRemaining: Int?) -> String? {
        guard let daysRemaining else { return nil }
        return daysRemaining == 1 ? "1 day left in Pro trial" : "\(daysRemaining) days left in Pro trial"
    }
}

enum MainViewSelectionPolicy {
    /// Choose selection on load without overriding a valid existing user selection.
    static func initialSelection(profiles: [Profile], isPro: Bool, currentSelection: Set<UUID>) -> Set<UUID> {
        let validProfileIDs = Set(profiles.map(\.id))
        let retainedSelection = currentSelection.intersection(validProfileIDs)
        if !retainedSelection.isEmpty {
            return retainedSelection
        }

        if let active = profiles.first(where: \.isActive) {
            return [active.id]
        }

        if !isPro,
           let essentials = profiles.first(where: { $0.name.caseInsensitiveCompare("Essentials") == .orderedSame }) {
            return [essentials.id]
        }

        if let first = profiles.first {
            return [first.id]
        }

        return []
    }
}

/// Main view with sidebar navigation - SaneClip design language
public struct MainView: View {
    var store: ProfileStore {
        ProfileStore.shared
    }

    var licenseService: LicenseService
    @State var selectedProfileIDs: Set<UUID> = []
    @State var showingNewProfile = false
    @State var showingTemplates = false
    @State var showingRemoteImport = false
    @State var showingMergeProfiles = false
    @State var showingDeleteConfirmation = false
    @State var showingRenameSheet = false
    @State var isActivating = false
    @State var activationError: String?
    @State var activationWarning: String?
    @State var showingActivationSuccess = false
    @State var selectedPreset: ProfilePreset?
    @State var isDownloadingPreset = false
    @State var proUpsellFeature: ProFeature?

    /// Selected profiles (computed from IDs)
    var selectedProfiles: [Profile] {
        store.profiles.filter { selectedProfileIDs.contains($0.id) }
    }

    /// Single selected profile (for detail view when one selected)
    var selectedProfile: Profile? {
        guard selectedProfileIDs.count == 1,
              let id = selectedProfileIDs.first else { return nil }
        return store.profiles.first { $0.id == id }
    }

    /// Presets that haven't been downloaded yet (not in profiles by name)
    var availablePresets: [ProfilePreset] {
        let existingNames = Set(store.profiles.map(\.name))
        return ProfilePreset.allCases.filter { !existingNames.contains($0.displayName) }
    }

    public init(licenseService: LicenseService) {
        self.licenseService = licenseService
    }

    public init() {
        self.init(licenseService: Self.defaultLicenseService())
    }

    private static func defaultLicenseService() -> LicenseService {
        LicenseService(
            appName: "SaneHosts",
            checkoutURL: LicenseService.directCheckoutURL(appSlug: "sanehosts"),
            keychain: SaneHostsLicenseKeychain.makeService(),
            proTrial: .init(storageKeyPrefix: "sanehosts.pro_trial")
        )
    }

    public var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 280, max: 350)
        } detail: {
            ZStack {
                SaneGradientBackground()
                detail
            }
        }
        .groupBoxStyle(GlassGroupBoxStyle())
        .onChange(of: selectedProfileIDs) { _, newValue in
            // Clear preset selection when a profile is selected
            if !newValue.isEmpty {
                selectedPreset = nil
            }
        }
        .task {
            await store.load()
            selectedProfileIDs = MainViewSelectionPolicy.initialSelection(
                profiles: store.profiles,
                isPro: licenseService.isPro,
                currentSelection: selectedProfileIDs
            )
            if !selectedProfileIDs.isEmpty {
                selectedPreset = nil
            }
        }
        .alert("Activation Failed", isPresented: .constant(activationError != nil)) {
            Button("OK") { activationError = nil }
        } message: {
            Text(activationError ?? "")
        }
        .alert("Warning", isPresented: .constant(activationWarning != nil)) {
            Button("OK") { activationWarning = nil }
        } message: {
            Text(activationWarning ?? "")
        }
        .overlay {
            if showingActivationSuccess {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    Text("Protection Active")
                        .font(.headline)
                }
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .transition(.scale.combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { showingActivationSuccess = false }
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete \(selectedProfileIDs.count) Profile\(selectedProfileIDs.count == 1 ? "" : "s")?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteSelectedProfiles()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if selectedProfiles.contains(where: \.isActive) {
                Text("Cannot delete active profiles. Deactivate them first.")
            } else {
                Text("This action cannot be undone.")
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button("Select All", action: selectAllProfiles)
                    .keyboardShortcut("a", modifiers: .command)
                Button {
                    if licenseService.isPro {
                        duplicateSelectedProfiles()
                    } else {
                        proUpsellFeature = .duplicateProfile
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Duplicate")
                        if !licenseService.isPro {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.teal)
                        }
                    }
                }
                .keyboardShortcut("d", modifiers: .command)
                Button {
                    if licenseService.isPro {
                        showingMergeProfiles = true
                    } else {
                        proUpsellFeature = .profileMerge
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Merge")
                        if !licenseService.isPro {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.teal)
                        }
                    }
                }
                .keyboardShortcut("m", modifiers: .command)
                Button("Export", action: exportSelectedProfiles)
                    .keyboardShortcut("e", modifiers: .command)
                Button("Delete", action: deleteWithConfirmation)
                    .keyboardShortcut(.delete, modifiers: .command)
                Button("Activate", action: activateFirstSelected)
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                Button("Deactivate", action: deactivateProfile)
                    .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }
        .onDeleteCommand {
            deleteWithConfirmation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showNewProfileSheet)) { _ in
            if licenseService.isPro || store.profiles.isEmpty {
                showingNewProfile = true
            } else {
                proUpsellFeature = .multipleProfiles
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showImportSheet)) { _ in
            if licenseService.isPro {
                showingRemoteImport = true
            } else {
                proUpsellFeature = .importProfiles
            }
        }
        .sheet(item: $proUpsellFeature) { feature in
            ProUpsellView(feature: feature, licenseService: licenseService)
        }
    }
}
