import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Main view with sidebar navigation - SaneClip design language
public struct MainView: View {
    @State private var store = ProfileStore()
    @State private var selectedProfileIDs: Set<UUID> = []
    @State private var showingNewProfile = false
    @State private var showingTemplates = false
    @State private var showingRemoteImport = false
    @State private var showingMergeProfiles = false
    @State private var showingDeleteConfirmation = false
    @State private var showingRenameSheet = false
    @State private var isActivating = false
    @State private var activationError: String?

    /// Selected profiles (computed from IDs)
    private var selectedProfiles: [Profile] {
        store.profiles.filter { selectedProfileIDs.contains($0.id) }
    }

    /// Single selected profile (for detail view when one selected)
    private var selectedProfile: Profile? {
        guard selectedProfileIDs.count == 1,
              let id = selectedProfileIDs.first else { return nil }
        return store.profiles.first { $0.id == id }
    }

    public init() {}

    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            ZStack {
                SaneGradientBackground()
                detail
            }
        }
        .groupBoxStyle(GlassGroupBoxStyle())
        .task {
            await store.load()
            if let first = store.profiles.first {
                selectedProfileIDs = [first.id]
            }
        }
        .alert("Activation Failed", isPresented: .constant(activationError != nil)) {
            Button("OK") { activationError = nil }
        } message: {
            Text(activationError ?? "")
        }
        // Confirmation dialog for delete
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
            if selectedProfiles.contains(where: { $0.isActive }) {
                Text("Cannot delete active profiles. Deactivate them first.")
            } else {
                Text("This action cannot be undone.")
            }
        }
        // Keyboard shortcuts toolbar
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button("Select All", action: selectAllProfiles)
                    .keyboardShortcut("a", modifiers: .command)
                Button("Duplicate", action: duplicateSelectedProfiles)
                    .keyboardShortcut("d", modifiers: .command)
                Button("Merge", action: { showingMergeProfiles = true })
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
        // Handle Delete key without modifiers for list items
        .onDeleteCommand {
            deleteWithConfirmation()
        }
        // Handle App Menu commands
        .onReceive(NotificationCenter.default.publisher(for: .showNewProfileSheet)) { _ in
            showingNewProfile = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showImportSheet)) { _ in
            showingRemoteImport = true
        }
    }

    // MARK: - Selection Actions

    private func selectAllProfiles() {
        selectedProfileIDs = Set(store.profiles.map(\.id))
    }

    private func deselectAllProfiles() {
        if let first = store.profiles.first {
            selectedProfileIDs = [first.id]
        } else {
            selectedProfileIDs = []
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $selectedProfileIDs) {
            // Quick Actions - All actions visible, no hidden menus
            Section {
                // Primary: Import Blocklist (most common)
                QuickActionButton(
                    title: "Import Blocklist",
                    subtitle: "From curated sources or URL",
                    icon: "arrow.down.circle.fill",
                    color: .blue
                ) {
                    showingRemoteImport = true
                }

                // New Empty Profile
                QuickActionButton(
                    title: "New Empty Profile",
                    subtitle: "Start from scratch",
                    icon: "plus.circle.fill",
                    color: .orange
                ) {
                    showingNewProfile = true
                }

                // From Template
                QuickActionButton(
                    title: "From Template",
                    subtitle: "Ad blocking, privacy, etc.",
                    icon: "doc.badge.plus",
                    color: .purple
                ) {
                    showingTemplates = true
                }

                // Merge Profiles (only show when useful)
                if store.profiles.count >= 2 {
                    QuickActionButton(
                        title: "Merge Profiles",
                        subtitle: "Combine \(store.profiles.count) profiles",
                        icon: "arrow.triangle.merge",
                        color: .pink
                    ) {
                        showingMergeProfiles = true
                    }
                }
            } header: {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("QUICK ACTIONS")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.primary.opacity(0.85))
            }

            Section {
                ForEach(store.profiles) { profile in
                    ProfileRowView(profile: profile)
                        .tag(profile.id)
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
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.primary.opacity(0.85))
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
    private var detail: some View {
        if selectedProfileIDs.count > 1 {
            // Multiple selection - show batch actions
            MultiSelectDetailView(
                profiles: selectedProfiles,
                onMerge: { showingMergeProfiles = true },
                onExport: { exportSelectedProfiles() },
                onDelete: { deleteWithConfirmation() },
                onActivate: { activateFirstSelected() }
            )
        } else if let profile = selectedProfile {
            // Single selection - show detail
            ProfileDetailView(
                profile: profile,
                store: store,
                onActivate: { activateProfile(profile) },
                onDeactivate: { deactivateProfile() }
            )
        } else {
            // No selection
            SaneEmptyState(
                icon: SaneIcons.hosts,
                title: "No Profile Selected",
                description: "Select a profile from the sidebar or create a new one.",
                actionTitle: "New Profile"
            ) {
                showingNewProfile = true
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func profileContextMenu(for profile: Profile) -> some View {
        if profile.isActive {
            Button {
                deactivateProfile()
            } label: {
                Label("Deactivate", systemImage: SaneIcons.deactivate)
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
            Task {
                if let newProfile = try? await store.duplicate(profile: profile) {
                    selectedProfileIDs = [newProfile.id]
                }
            }
        } label: {
            Label("Duplicate", systemImage: SaneIcons.duplicate)
        }

        Button {
            exportProfile(profile)
        } label: {
            Label("Export...", systemImage: SaneIcons.export)
        }

        Divider()

        Button(role: .destructive) {
            // If multiple profiles selected and this profile is in selection, delete all selected
            if selectedProfileIDs.count > 1 && selectedProfileIDs.contains(profile.id) {
                deleteWithConfirmation()
            } else {
                deleteProfile(profile)
            }
        } label: {
            // Show count if multiple selected and this profile is in selection
            if selectedProfileIDs.count > 1 && selectedProfileIDs.contains(profile.id) {
                Label("Delete \(selectedProfileIDs.count) Profiles", systemImage: SaneIcons.remove)
            } else {
                Label("Delete", systemImage: SaneIcons.remove)
            }
        }
        .disabled(profile.isActive)
    }

    // MARK: - Single Profile Actions

    private func activateProfile(_ profile: Profile) {
        isActivating = true
        Task {
            do {
                try await HostsService.shared.activateProfile(profile, systemEntries: store.systemEntries)
                try await store.markAsActive(profile: profile)
            } catch {
                activationError = error.localizedDescription
            }
            isActivating = false
        }
    }

    private func deactivateProfile() {
        isActivating = true
        Task {
            do {
                try await HostsService.shared.deactivateProfile()
                try await store.deactivate()
            } catch {
                activationError = error.localizedDescription
            }
            isActivating = false
        }
    }

    private func deleteProfile(_ profile: Profile) {
        Task {
            try? await store.delete(profile: profile)
            selectedProfileIDs.remove(profile.id)
            if selectedProfileIDs.isEmpty, let first = store.profiles.first {
                selectedProfileIDs = [first.id]
            }
        }
    }

    private func exportProfile(_ profile: Profile) {
        let content = store.exportProfile(profile)

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(profile.name).hosts"

        if panel.runModal() == .OK, let url = panel.url {
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Multi-Select Actions

    private func deleteWithConfirmation() {
        guard !selectedProfileIDs.isEmpty else { return }
        // Count deletable (non-active) profiles
        let deletableCount = selectedProfiles.filter { !$0.isActive }.count
        if deletableCount == 0 {
            activationError = "Cannot delete active profiles. Deactivate them first."
            return
        }
        showingDeleteConfirmation = true
    }

    private func deleteSelectedProfiles() {
        // Capture IDs of non-active profiles to delete
        let idsToDelete = selectedProfiles.filter { !$0.isActive }.map(\.id)
        guard !idsToDelete.isEmpty else { return }

        // Clear selection and delete synchronously to avoid race conditions
        selectedProfileIDs = []
        store.deleteProfiles(ids: idsToDelete)

        // Select first remaining profile
        if let first = store.profiles.first {
            selectedProfileIDs = [first.id]
        }
    }

    private func duplicateSelectedProfiles() {
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

    private func exportSelectedProfiles() {
        if selectedProfiles.count == 1, let profile = selectedProfiles.first {
            exportProfile(profile)
            return
        }

        // Multiple profiles - let user pick folder
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose folder to export \(selectedProfiles.count) profiles"

        if panel.runModal() == .OK, let folderURL = panel.url {
            for profile in selectedProfiles {
                let content = store.exportProfile(profile)
                let fileURL = folderURL.appendingPathComponent("\(profile.name).hosts")
                try? content.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        }
    }

    private func activateFirstSelected() {
        guard let profile = selectedProfiles.first else { return }
        activateProfile(profile)
    }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.primary.opacity(0.7))
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}

// MARK: - Profile Row

struct ProfileRowView: View {
    let profile: Profile

    var body: some View {
        HStack(spacing: 12) {
            // Semantic color based on source type (remote=blue, merged=purple, local=gray)
            ProfileColorDot(color: profile.source.semanticColor)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(profile.name)
                        .font(.body)
                        .fontWeight(profile.isActive ? .semibold : .regular)
                        .lineLimit(1)

                    // Source indicator icon
                    if profile.source.isRemote {
                        Image(systemName: SaneIcons.profileRemote)
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    } else if profile.source.isMerged {
                        Image(systemName: "arrow.triangle.merge")
                            .font(.subheadline)
                            .foregroundStyle(.purple)
                    }
                }

                Text(entrySummary)
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.6))
            }

            Spacer()

            if profile.isActive {
                StatusBadge("Active", color: .saneSuccess, icon: SaneIcons.success)
            }
        }
        .padding(.vertical, 5)
    }

    private var entrySummary: String {
        let count = profile.entries.count
        if count == 0 {
            return "Empty"
        } else if count == 1 {
            return "1 entry"
        } else {
            // Use compact notation for large numbers (10K instead of 10000)
            let formatted = count.formatted(.number.notation(.compactName))
            return "\(formatted) entries"
        }
    }
}

// MARK: - Multi-Select Detail View

struct MultiSelectDetailView: View {
    let profiles: [Profile]
    let onMerge: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void
    let onActivate: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var totalEntries: Int {
        profiles.reduce(0) { $0 + $1.entries.count }
    }

    private var hasActiveProfile: Bool {
        profiles.contains(where: { $0.isActive })
    }

    var body: some View {
        VStack(spacing: 32) {
            // Header with count
            VStack(spacing: 12) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.blue)

                Text("\(profiles.count) Profiles Selected")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(totalEntriesSummary)
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.7))
            }

            // Selected profiles list
            VStack(alignment: .leading, spacing: 10) {
                Text("Selected")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary.opacity(0.7))
                    .padding(.leading, 4)

                VStack(spacing: 0) {
                    ForEach(profiles) { profile in
                        HStack(spacing: 10) {
                            ProfileColorDot(color: profile.source.semanticColor)

                            Text(profile.name)
                                .lineLimit(1)

                            Spacer()

                            if profile.isActive {
                                StatusBadge("Active", color: .saneSuccess, icon: SaneIcons.success)
                            }

                            Text(profile.entries.count.formatted(.number.notation(.compactName)))
                                .font(.subheadline)
                                .foregroundStyle(.primary.opacity(0.5))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        if profile.id != profiles.last?.id {
                            Divider().padding(.leading, 32)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
                )
            }
            .frame(maxWidth: 400)

            // Actions
            VStack(spacing: 12) {
                // Primary action: Merge
                Button(action: onMerge) {
                    HStack {
                        Image(systemName: "arrow.triangle.merge")
                        Text("Merge into New Profile")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .controlSize(.large)

                HStack(spacing: 12) {
                    // Export
                    Button(action: onExport) {
                        HStack {
                            Image(systemName: SaneIcons.export)
                            Text("Export All")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    // Activate first
                    Button(action: onActivate) {
                        HStack {
                            Image(systemName: SaneIcons.activate)
                            Text("Activate First")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                // Delete
                Button(role: .destructive, action: onDelete) {
                    HStack {
                        Image(systemName: SaneIcons.remove)
                        Text("Delete Selected")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(hasActiveProfile)

                if hasActiveProfile {
                    Text("Cannot delete active profiles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 300)

            Spacer()
        }
        .padding(40)
    }

    private var totalEntriesSummary: String {
        let formatted = totalEntries.formatted(.number.notation(.compactName))
        return "\(formatted) total entries"
    }
}

// MARK: - New Profile Sheet

struct NewProfileSheet: View {
    let store: ProfileStore
    let onCreated: (Profile) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var name = ""
    @State private var selectedColor: ProfileColor = .blue

    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Image(systemName: SaneIcons.add)
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("New Profile")
                    .font(.headline)
            }

            // Form
            VStack(spacing: 16) {
                CompactSection("Profile Name", icon: "textformat", iconColor: .blue) {
                    TextField("My Profile", text: $name)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }

                CompactSection("Color Tag", icon: "paintpalette", iconColor: .purple) {
                    HStack(spacing: 12) {
                        ForEach(ProfileColor.allCases, id: \.self) { color in
                            Button {
                                selectedColor = color
                            } label: {
                                Circle()
                                    .fill(colorForTag(color))
                                    .frame(width: 24, height: 24)
                                    .overlay {
                                        if selectedColor == color {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }

            // Actions
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)

                Button("Create") {
                    Task {
                        if let profile = try? await store.create(name: name) {
                            onCreated(profile)
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.saneAccent)
                .disabled(name.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
        .background(SaneGradientBackground())
    }

    private func colorForTag(_ tag: ProfileColor) -> Color {
        switch tag {
        case .gray: return .gray
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        }
    }
}

// MARK: - Template Picker

struct TemplatePickerSheet: View {
    let store: ProfileStore
    let onCreated: (Profile) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Image(systemName: "doc.badge.plus")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("Create from Template")
                    .font(.headline)
            }

            // Templates
            VStack(spacing: 12) {
                ForEach(ProfileTemplate.allCases, id: \.name) { template in
                    TemplateRow(template: template) {
                        Task {
                            if let profile = try? await store.create(name: template.name, from: template) {
                                onCreated(profile)
                                dismiss()
                            }
                        }
                    }
                }
            }

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(width: 420)
        .background(SaneGradientBackground())
    }
}

struct TemplateRow: View {
    let template: ProfileTemplate
    let onSelect: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: iconForTemplate)
                    .font(.title2)
                    .foregroundStyle(colorForTemplate)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text(template.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(template.entries.count.formatted(.number.notation(.compactName))) entries")
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.5))

                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.4))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var iconForTemplate: String {
        switch template {
        case .adBlocking: return SaneIcons.templateAdBlock
        case .development: return SaneIcons.templateDev
        case .social: return SaneIcons.templateSocial
        case .privacy: return SaneIcons.templatePrivacy
        }
    }

    private var colorForTemplate: Color {
        switch template {
        case .adBlocking: return .red
        case .development: return .blue
        case .social: return .purple
        case .privacy: return .mint
        }
    }
}

// MARK: - Remote Import Sheet (Blocklist Catalog)

struct RemoteImportSheet: View {
    let store: ProfileStore
    let onCreated: (Profile) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    // Selection state
    @State private var selectedSources: Set<String> = []
    @State private var profileName = ""
    @State private var previousSuggestedName = ""  // Track auto-filled value to detect user edits
    @State private var expandedCategories: Set<BlocklistCategory> = [.recommended, .adsTrackers]

    // Import state
    @State private var isImporting = false
    @State private var importProgress: Double = 0
    @State private var currentImportName = ""
    @State private var error: String?

    // Custom URL
    @State private var showingCustomURL = false
    @State private var customURL = ""

    // URL liveness checking
    @State private var urlStatus: [String: URLCheckStatus] = [:]
    @State private var isCheckingURLs = false

    enum URLCheckStatus: Equatable {
        case checking
        case available
        case unavailable(Int) // HTTP status code
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            Divider()

            // Scrollable content
            ScrollView {
                VStack(spacing: 16) {
                    // Categories with blocklists
                    ForEach(BlocklistCatalog.availableCategories, id: \.self) { category in
                        categorySection(category)
                    }

                    // Custom URL option
                    customURLSection
                }
                .padding(20)
            }

            Divider()

            // Footer with actions
            footer
                .padding(20)
        }
        .frame(width: 520, height: 600)
        .background(SaneGradientBackground())
        .overlay {
            if isImporting {
                importProgressOverlay
            }
        }
        .onChange(of: selectedSources) { _, newValue in
            // Auto-fill name when selection changes (only if user hasn't typed a custom name)
            if !newValue.isEmpty && (profileName.isEmpty || profileName == previousSuggestedName) {
                profileName = suggestedName
                previousSuggestedName = suggestedName
            }
        }
        .onChange(of: customURL) { _, newValue in
            // Auto-fill name when custom URL changes (only if user hasn't typed a custom name)
            if !newValue.isEmpty && (profileName.isEmpty || profileName == previousSuggestedName) {
                profileName = suggestedName
                previousSuggestedName = suggestedName
            }
        }
        .onAppear {
            checkAllURLs()
        }
    }

    // MARK: - URL Liveness Checking

    private func checkAllURLs() {
        guard urlStatus.isEmpty else { return } // Only check once per sheet open

        isCheckingURLs = true

        // Mark all as checking
        for source in BlocklistCatalog.all {
            urlStatus[source.id] = .checking
        }

        // Check all URLs in parallel
        Task {
            await withTaskGroup(of: (String, URLCheckStatus).self) { group in
                for source in BlocklistCatalog.all {
                    group.addTask {
                        let status = await self.checkURL(source.url)
                        return (source.id, status)
                    }
                }

                for await (id, status) in group {
                    await MainActor.run {
                        urlStatus[id] = status
                    }
                }
            }

            await MainActor.run {
                isCheckingURLs = false
            }
        }
    }

    private func checkURL(_ url: URL) async -> URLCheckStatus {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if (200...399).contains(httpResponse.statusCode) {
                    return .available
                } else {
                    return .unavailable(httpResponse.statusCode)
                }
            }
            return .available
        } catch {
            return .unavailable(0) // Network error
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title)
                    .foregroundStyle(.blue)
                Text("Import Blocklists")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()

                // URL checking status
                if isCheckingURLs {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Checking URLs...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    let unavailableCount = urlStatus.values.filter {
                        if case .unavailable = $0 { return true }
                        return false
                    }.count

                    if unavailableCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text("\(unavailableCount) unavailable")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            Text("Select one or more blocklists to import. Multiple selections will be merged into a single profile.")
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Category Section

    private func categorySection(_ category: BlocklistCategory) -> some View {
        let sources = BlocklistCatalog.sources(for: category)
        let isExpanded = expandedCategories.contains(category)
        let selectedInCategory = sources.filter { selectedSources.contains($0.id) }.count

        return VStack(spacing: 0) {
            // Category header (clickable to expand/collapse)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedCategories.remove(category)
                    } else {
                        expandedCategories.insert(category)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: category.icon)
                        .font(.body)
                        .foregroundStyle(categoryColor(category))
                        .frame(width: 24)

                    Text(category.rawValue)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    if selectedInCategory > 0 {
                        Text("\(selectedInCategory)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(categoryColor(category).opacity(0.2))
                            .foregroundStyle(categoryColor(category))
                            .clipShape(Capsule())
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.subheadline)
                        .foregroundStyle(.primary.opacity(0.5))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Blocklist items (when expanded)
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(sources) { source in
                        blocklistRow(source)
                        if source.id != sources.last?.id {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .background(colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private func blocklistRow(_ source: BlocklistSource) -> some View {
        let isSelected = selectedSources.contains(source.id)
        let status = urlStatus[source.id]
        let isUnavailable = if case .unavailable = status { true } else { false }

        return Button {
            guard !isUnavailable else { return } // Don't allow selecting unavailable sources

            if isSelected {
                selectedSources.remove(source.id)
            } else {
                selectedSources.insert(source.id)
            }
        } label: {
            HStack(spacing: 12) {
                // Checkbox
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.blue : Color.secondary.opacity(isUnavailable ? 0.3 : 1.0))

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(source.name)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary.opacity(isUnavailable ? 0.4 : 1.0))

                        if source.isRecommended && !isUnavailable {
                            Text("Recommended")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.2))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }

                    Text(source.description)
                        .font(.subheadline)
                        .foregroundStyle(.primary.opacity(isUnavailable ? 0.3 : 0.6))
                        .lineLimit(2)
                }

                Spacer()

                // Entry count estimate
                Text(source.estimatedEntries)
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(isUnavailable ? 0.2 : 0.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(isUnavailable ? 0.05 : 0.15))
                    .clipShape(Capsule())

                // URL status indicator
                urlStatusBadge(for: status)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isUnavailable ? 0.6 : 1.0)
    }

    @ViewBuilder
    private func urlStatusBadge(for status: URLCheckStatus?) -> some View {
        switch status {
        case .checking:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 20, height: 20)
        case .available:
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.green)
        case .unavailable(let code):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                if code > 0 {
                    Text("\(code)")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        case .none:
            EmptyView()
        }
    }

    // MARK: - Custom URL Section

    private var customURLSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation {
                    showingCustomURL.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "link")
                        .font(.body)
                        .foregroundStyle(.blue)
                        .frame(width: 24)

                    Text("Custom URL")
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: showingCustomURL ? "chevron.down" : "chevron.right")
                        .font(.subheadline)
                        .foregroundStyle(.primary.opacity(0.5))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showingCustomURL {
                HStack {
                    TextField("https://example.com/hosts.txt", text: $customURL)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(colorScheme == .dark ? Color.black.opacity(0.2) : Color.white)
                        .cornerRadius(6)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 14) {
            // Profile name (shown when selections made)
            if !selectedSources.isEmpty || !customURL.isEmpty {
                HStack {
                    Text("Profile Name:")
                        .font(.body)
                        .foregroundStyle(.primary.opacity(0.7))
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
                if selectedSources.isEmpty && customURL.isEmpty {
                    Text("Select blocklists to import")
                        .font(.subheadline)
                        .foregroundStyle(.primary.opacity(0.6))
                } else if selectedSources.count == 1 {
                    Text("1 blocklist selected")
                        .font(.subheadline)
                        .foregroundStyle(.primary.opacity(0.7))
                } else if selectedSources.count > 1 {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.merge")
                            .font(.subheadline)
                            .foregroundStyle(.purple)
                        Text("\(selectedSources.count) blocklists will be merged")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.purple)
                    }
                } else if !customURL.isEmpty {
                    Text("Custom URL ready to import")
                        .font(.subheadline)
                        .foregroundStyle(.primary.opacity(0.7))
                }

                Spacer()

                // Error display
                if let error = error {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }

                // Buttons
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)

                Button(importButtonTitle) {
                    startImport()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(selectedSources.count > 1 ? .purple : .saneAccent)
                .disabled(selectedSources.isEmpty && customURL.isEmpty)
            }
        }
    }

    private var importButtonTitle: String {
        if selectedSources.count > 1 {
            return "Import & Merge"
        } else {
            return "Import"
        }
    }

    private var suggestedName: String {
        if selectedSources.count == 1 {
            let sourceId = selectedSources.first!
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

    private func generateCombinedName(from sources: [BlocklistSource]) -> String {
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

    private func shortenSourceName(_ name: String) -> String {
        var shortened = name
        // Remove common words to keep names concise
        let removables = ["Steven Black ", " Unified", " Basic", " Default", " Block", " List", " Filter"]
        for removable in removables {
            shortened = shortened.replacingOccurrences(of: removable, with: "")
        }
        return shortened.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Import Progress Overlay

    private var importProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView(value: importProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)
                    .tint(.blue)

                Text(currentImportName)
                    .font(.callout)
                    .foregroundStyle(.white)

                if selectedSources.count > 1 {
                    Text("Importing \(Int(importProgress * Double(selectedSources.count))) of \(selectedSources.count)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Button("Cancel") {
                    // Cancel would need task tracking
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )
        }
    }

    // MARK: - Helpers

    private func categoryColor(_ category: BlocklistCategory) -> Color {
        switch category {
        case .recommended: return .orange
        case .adsTrackers: return .blue
        case .malwareSecurity: return .red
        case .privacy: return .mint
        case .socialMedia: return .purple
        case .gambling: return .yellow
        case .fakeNews: return .pink
        case .adult: return .gray
        case .annoyances: return .cyan
        case .regional: return .indigo
        }
    }

    // MARK: - Import Logic

    private func startImport() {
        let finalName = profileName.isEmpty ? suggestedName : profileName
        isImporting = true
        importProgress = 0
        error = nil

        Task { @MainActor in
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

                for (index, source) in sources.enumerated() {
                    currentImportName = "Downloading \(source.name)..."
                    importProgress = Double(index) / Double(sources.count)

                    let remoteFile = try await RemoteSyncService.shared.fetch(from: source.url)

                    // Deduplicate as we go
                    for entry in remoteFile.entries {
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
                let profile: Profile
                if sources.count == 1 {
                    // Single source - create as remote
                    profile = try await store.createRemote(
                        name: finalName,
                        url: sources[0].url,
                        entries: allEntries
                    )
                } else {
                    // Multiple sources - create as merged
                    profile = try await store.createMerged(
                        name: finalName,
                        entries: allEntries,
                        sourceCount: sources.count
                    )
                }

                onCreated(profile)
                dismiss()

            } catch {
                self.error = error.localizedDescription
                isImporting = false
            }
        }
    }
}

// MARK: - Fetch Progress Overlay

struct FetchProgressOverlay: View {
    let onCancel: () -> Void

    var syncService: RemoteSyncService { RemoteSyncService.shared }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // Phase-based progress display
                switch syncService.phase {
                case .connecting:
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Connecting...")
                        .font(.callout)
                        .foregroundStyle(.white)

                case .downloading:
                    if !syncService.isIndeterminate {
                        // Determinate progress bar
                        ProgressView(value: syncService.downloadProgress)
                            .progressViewStyle(.linear)
                            .frame(width: 200)
                            .tint(.blue)

                        Text(String(format: "%.0f%%", syncService.downloadProgress * 100))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    } else {
                        // Indeterminate - show downloaded bytes
                        ProgressView()
                            .scaleEffect(1.2)
                    }
                    Text(syncService.statusMessage)
                        .font(.callout)
                        .foregroundStyle(.white)

                case .parsing:
                    ProgressView(value: syncService.parseProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 200)
                        .tint(.orange)
                    Text(syncService.statusMessage)
                        .font(.callout)
                        .foregroundStyle(.white)

                case .saving:
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Saving...")
                        .font(.callout)
                        .foregroundStyle(.white)

                case .complete:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.blue)
                    Text(syncService.statusMessage)
                        .font(.callout)
                        .foregroundStyle(.white)

                case .idle, .error:
                    ProgressView()
                        .scaleEffect(1.2)
                    Text(syncService.statusMessage.isEmpty ? "Connecting..." : syncService.statusMessage)
                        .font(.callout)
                        .foregroundStyle(.white)
                }

                // Cancel button - always available during import
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )
        }
    }
}

// MARK: - Merge Profiles Sheet

struct MergeProfilesSheet: View {
    let store: ProfileStore
    let preselectedIDs: Set<UUID>
    let onCreate: (Profile) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedProfiles: Set<UUID> = []
    @State private var mergedName = ""
    @State private var previousSuggestedName = ""
    @State private var isMerging = false
    @State private var error: String?

    private var suggestedName: String {
        let profiles = store.profiles.filter { selectedProfiles.contains($0.id) }
        return generateMergedName(from: profiles)
    }

    init(store: ProfileStore, preselectedIDs: Set<UUID> = [], onCreate: @escaping (Profile) -> Void) {
        self.store = store
        self.preselectedIDs = preselectedIDs
        self.onCreate = onCreate
        // Initialize state with preselected IDs
        _selectedProfiles = State(initialValue: preselectedIDs)
    }

    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Image(systemName: "arrow.triangle.merge")
                    .font(.title2)
                    .foregroundStyle(.purple)
                Text("Merge Profiles")
                    .font(.headline)
            }

            Text("Select profiles to combine into one. Duplicate entries will be removed.")
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.7))
                .multilineTextAlignment(.center)

            // Profile selection list
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(store.profiles) { profile in
                        Button {
                            toggleSelection(profile)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedProfiles.contains(profile.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selectedProfiles.contains(profile.id) ? .purple : .primary.opacity(0.4))

                                ProfileColorDot(color: profile.colorTag)

                                Text(profile.name)
                                    .font(.body)
                                    .foregroundStyle(.primary)

                                Spacer()

                                Text("\(profile.entries.count.formatted(.number.notation(.compactName))) entries")
                                    .font(.subheadline)
                                    .foregroundStyle(.primary.opacity(0.6))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedProfiles.contains(profile.id) ? Color.purple.opacity(0.1) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 200)

            // Merged profile name
            CompactSection("New Profile Name", icon: "textformat", iconColor: .purple) {
                TextField(suggestedName, text: $mergedName)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .onChange(of: selectedProfiles) { _, newValue in
                // Auto-fill name when selection changes (only if user hasn't typed anything)
                if mergedName.isEmpty || mergedName == previousSuggestedName {
                    let profiles = store.profiles.filter { newValue.contains($0.id) }
                    mergedName = generateMergedName(from: profiles)
                    previousSuggestedName = mergedName
                }
            }

            // Stats
            if selectedProfiles.count >= 2 {
                let totalEntries = store.profiles.filter { selectedProfiles.contains($0.id) }.reduce(0) { $0 + $1.entries.count }
                Text("Will combine ~\(totalEntries) entries (duplicates removed)")
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.6))
            }

            if let error = error {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }

            // Actions
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)

                Button("Merge") {
                    mergeProfiles()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(selectedProfiles.count < 2 || mergedName.isEmpty || isMerging)
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(SaneGradientBackground())
        .onAppear {
            // Auto-fill name on appear if profiles are preselected
            if !selectedProfiles.isEmpty && mergedName.isEmpty {
                let profiles = store.profiles.filter { selectedProfiles.contains($0.id) }
                mergedName = generateMergedName(from: profiles)
                previousSuggestedName = mergedName
            }
        }
    }

    private func toggleSelection(_ profile: Profile) {
        if selectedProfiles.contains(profile.id) {
            selectedProfiles.remove(profile.id)
        } else {
            selectedProfiles.insert(profile.id)
        }
    }

    private func mergeProfiles() {
        isMerging = true
        error = nil

        let profilesToMerge = store.profiles.filter { selectedProfiles.contains($0.id) }
        let nameToUse = mergedName.isEmpty ? generateMergedName(from: profilesToMerge) : mergedName

        Task { @MainActor in
            do {
                let merged = try await store.merge(profiles: profilesToMerge, name: nameToUse)
                onCreate(merged)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            isMerging = false
        }
    }

    private func generateMergedName(from profiles: [Profile]) -> String {
        guard !profiles.isEmpty else { return "Merged Profile" }

        // If 2-3 profiles, combine their names smartly
        if profiles.count <= 3 {
            let names = profiles.map { shortenName($0.name) }
            return names.joined(separator: " + ")
        }

        // For 4+ profiles, use first name + count
        let firstName = shortenName(profiles[0].name)
        return "\(firstName) + \(profiles.count - 1) more"
    }

    private func shortenName(_ name: String) -> String {
        // Remove common prefixes/suffixes to make combined names shorter
        var shortened = name
        let removables = ["StevenBlack ", "Blocklist", " Hosts", " List"]
        for removable in removables {
            shortened = shortened.replacingOccurrences(of: removable, with: "")
        }
        // Trim and limit length
        shortened = shortened.trimmingCharacters(in: .whitespaces)
        if shortened.count > 20 {
            shortened = String(shortened.prefix(17)) + "..."
        }
        return shortened.isEmpty ? name : shortened
    }
}

#Preview {
    MainView()
}
