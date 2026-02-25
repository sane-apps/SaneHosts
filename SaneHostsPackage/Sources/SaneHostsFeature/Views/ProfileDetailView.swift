import SwiftUI

/// Detail view for editing a profile - SaneClip design language
struct ProfileDetailView: View {
    let profile: Profile
    let store: ProfileStore
    let onActivate: () -> Void
    let onDeactivate: () -> Void
    var licenseService: LicenseService

    @State private var showingAddEntry = false
    @State private var editingEntry: HostEntry?
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?

    // Bulk selection state
    @State private var isSelectionMode = false
    @State private var selectedEntries: Set<UUID> = []
    @State private var proUpsellFeature: ProFeature?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header card
                profileHeaderCard

                // Stats row
                statsRow

                // Bulk actions bar (when in selection mode)
                if isSelectionMode {
                    bulkActionsBar
                }

                // Entries section
                if !profile.entries.isEmpty {
                    entriesSection
                } else {
                    emptyState
                }
            }
            .padding(20)
        }
        .searchable(text: $searchText, prompt: "Filter entries")
        .onChange(of: searchText) { _, newValue in
            // Cancel previous debounce task
            searchDebounceTask?.cancel()

            // If empty, update immediately
            if newValue.isEmpty {
                debouncedSearchText = ""
                return
            }

            // Debounce: wait 300ms before filtering
            searchDebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                if !Task.isCancelled {
                    debouncedSearchText = newValue
                }
            }
        }
        .sheet(isPresented: $showingAddEntry) {
            AddEntrySheet(store: store, profile: profile)
        }
        .sheet(item: $editingEntry) { entry in
            EditEntrySheet(store: store, profile: profile, entry: entry)
        }
        .sheet(item: $proUpsellFeature) { feature in
            ProUpsellView(feature: feature, licenseService: licenseService)
        }
    }

    // MARK: - Computed

    private var filteredEntries: [HostEntry] {
        // Use debounced text for filtering large datasets
        if debouncedSearchText.isEmpty {
            return profile.entries
        }
        let query = debouncedSearchText.lowercased()
        return profile.entries.filter { entry in
            entry.ipAddress.lowercased().contains(query) ||
                entry.hostnames.contains { $0.lowercased().contains(query) } ||
                (entry.comment?.lowercased().contains(query) ?? false)
        }
    }

    // MARK: - Header Card

    private var profileHeaderCard: some View {
        CompactSection(profile.name, icon: SaneIcons.profiles, iconColor: .saneAccent) {
            VStack(spacing: 0) {
                // Status row
                HStack {
                    ProfileColorDot(color: profile.colorTag)

                    if profile.isActive {
                        StatusBadge("Active", color: .saneSuccess, icon: SaneIcons.success)
                            .accessibilityLabel("Profile status: Active")
                    } else {
                        StatusBadge("Inactive", color: .secondary, icon: SaneIcons.profileInactive)
                            .accessibilityLabel("Profile status: Inactive")
                    }

                    Spacer()

                    // Action button
                    if profile.isActive {
                        Button {
                            onDeactivate()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: SaneIcons.deactivate)
                                Text("Deactivate")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .accessibilityLabel("Deactivate profile")
                        .accessibilityHint("Double-tap to deactivate this profile")
                    } else {
                        Button {
                            onActivate()
                            // Complete tutorial when user activates
                            if TutorialState.shared.currentStep == .activateProfile {
                                TutorialState.shared.completeTutorial()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: SaneIcons.activate)
                                Text("Activate")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.saneAccent) // Futuristic teal accent
                        .activateButtonAnchor()
                        .accessibilityLabel("Activate profile")
                        .accessibilityHint("Double-tap to activate this profile")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                CompactDivider()

                // Source info
                CompactRow("Source", icon: sourceIcon, iconColor: .saneAccent) {
                    Text(profile.source.displayName)
                        .foregroundStyle(.primary)
                }

                CompactDivider()

                // Modified date
                CompactRow("Modified", icon: "clock", iconColor: .saneAccent) {
                    Text(profile.modifiedAt, style: .relative)
                        .foregroundStyle(.primary)
                }

                // Remote source freshness indicator
                if case let .remote(url, lastFetched) = profile.source {
                    CompactDivider()
                    CompactRow("Source URL", icon: "link", iconColor: .blue) {
                        Text(url.host ?? url.absoluteString)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }

                    CompactDivider()
                    CompactRow("Last Fetched", icon: freshnessIcon(for: lastFetched), iconColor: freshnessColor(for: lastFetched)) {
                        HStack(spacing: 6) {
                            if let lastFetched {
                                Text(lastFetched, style: .relative)
                                    .font(.body)
                                    .foregroundStyle(.primary) // Readable text
                                FreshnessIndicator(date: lastFetched) // Colored badge shows status
                            } else {
                                Text("Never")
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Freshness Helpers

    private func freshnessIcon(for date: Date?) -> String {
        guard let date else { return "exclamationmark.circle" }
        let hours = Date().timeIntervalSince(date) / 3600
        if hours < 24 { return "checkmark.circle" }
        if hours < 168 { return "clock" } // 7 days
        return "exclamationmark.triangle"
    }

    private func freshnessColor(for date: Date?) -> Color {
        guard let date else { return .orange }
        let hours = Date().timeIntervalSince(date) / 3600
        if hours < 24 { return .blue } // Fresh - use blue to differentiate from Active green
        if hours < 168 { return .secondary } // 7 days
        return .orange
    }

    private var sourceIcon: String {
        switch profile.source {
        case .local: SaneIcons.profileLocal
        case .remote: SaneIcons.profileRemote
        case .merged: "arrow.triangle.merge"
        case .system: SaneIcons.profileSystem
        }
    }

    // MARK: - Stats Row

    private func compactNumber(_ n: Int) -> String {
        n.formatted(.number.notation(.compactName))
    }

    /// Cached entry counts - computed once per profile change
    private var cachedEntryCounts: (enabled: Int, disabled: Int) {
        profile.entryCounts
    }

    private var statsRow: some View {
        let counts = cachedEntryCounts // Compute once for this render
        return HStack(spacing: 16) {
            StatCard(
                title: "Total",
                value: compactNumber(profile.entries.count),
                icon: SaneIcons.hosts,
                color: .saneAccent
            )

            StatCard(
                title: "Enabled",
                value: compactNumber(counts.enabled),
                icon: SaneIcons.entryEnabled,
                color: .saneAccent
            )

            StatCard(
                title: "Disabled",
                value: compactNumber(counts.disabled),
                icon: SaneIcons.entryDisabled,
                color: .secondary
            )

            // Prominent Add Entry button - always visible
            Button {
                showingAddEntry = true
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title)
                        .foregroundStyle(.orange) // Orange for action - distinct from blue/teal
                    Text("Add Entry")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(colorScheme == .dark ? Color.orange.opacity(0.3) : Color.orange.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("Add a custom hosts entry to this profile")
            .accessibilityLabel("Add new host entry")
        }
    }

    // MARK: - Bulk Actions Bar

    private var bulkActionsBar: some View {
        HStack(spacing: 12) {
            // Selection count
            Text("\(selectedEntries.count) selected")
                .font(.callout)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            Spacer()

            // Select All / Deselect All
            Button {
                if selectedEntries.count == filteredEntries.count {
                    selectedEntries.removeAll()
                } else {
                    selectedEntries = Set(filteredEntries.map(\.id))
                }
            } label: {
                Text(selectedEntries.count == filteredEntries.count ? "Deselect All" : "Select All")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(selectedEntries.count == filteredEntries.count ? "Deselect all entries" : "Select all entries")

            Divider()
                .frame(height: 20)

            // Bulk Enable
            Button {
                bulkEnableSelected()
            } label: {
                Label("Enable", systemImage: SaneIcons.entryEnabled)
            }
            .buttonStyle(.bordered)
            .tint(.saneAccent)
            .disabled(selectedEntries.isEmpty)
            .accessibilityLabel("Enable selected entries")

            // Bulk Disable
            Button {
                bulkDisableSelected()
            } label: {
                Label("Disable", systemImage: SaneIcons.entryDisabled)
            }
            .buttonStyle(.bordered)
            .disabled(selectedEntries.isEmpty)
            .accessibilityLabel("Disable selected entries")

            // Bulk Delete
            Button(role: .destructive) {
                bulkDeleteSelected()
            } label: {
                Label("Delete", systemImage: SaneIcons.remove)
            }
            .buttonStyle(.bordered)
            .disabled(selectedEntries.isEmpty)
            .accessibilityLabel("Delete selected entries")

            Divider()
                .frame(height: 20)

            // Done button
            Button("Done") {
                isSelectionMode = false
                selectedEntries.removeAll()
            }
            .buttonStyle(.borderedProminent)
            .tint(.saneAccent)
            .help("Exit selection mode")
            .accessibilityLabel("Done selecting")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.saneAccent.opacity(0.1) : Color.saneAccent.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.saneAccent.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Entries Section

    /// Maximum entries to display before showing "Load More"
    private static let maxVisibleEntries = 100

    private var entriesSection: some View {
        CompactSection("Entries", icon: SaneIcons.hosts, iconColor: .saneAccent) {
            VStack(spacing: 0) {
                // Header with count and selection toggle
                HStack {
                    if filteredEntries.count > Self.maxVisibleEntries {
                        Text("Showing \(compactNumber(min(filteredEntries.count, Self.maxVisibleEntries))) of \(compactNumber(filteredEntries.count)) entries")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(compactNumber(filteredEntries.count)) entries")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    // Selection mode toggle (bulk operations = Pro)
                    if !profile.entries.isEmpty, !isSelectionMode {
                        Button {
                            if licenseService.isPro {
                                isSelectionMode = true
                            } else {
                                proUpsellFeature = .bulkOperations
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Label("Select", systemImage: "checkmark.circle")
                                if !licenseService.isPro {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.teal)
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(licenseService.isPro ? "Select entries for bulk enable, disable, or delete" : "Bulk operations require SaneHosts Pro")
                        .accessibilityLabel(licenseService.isPro ? "Enter selection mode" : "Bulk operations — Pro feature")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                CompactDivider()

                // Entries list - LIMITED to prevent UI freeze
                let visibleEntries = Array(filteredEntries.prefix(Self.maxVisibleEntries))
                ForEach(Array(visibleEntries.enumerated()), id: \.element.id) { index, entry in
                    HStack(spacing: 0) {
                        // Selection checkbox (when in selection mode)
                        if isSelectionMode {
                            Button {
                                toggleSelection(entry)
                            } label: {
                                Image(systemName: selectedEntries.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .foregroundStyle(selectedEntries.contains(entry.id) ? .blue : .secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(selectedEntries.contains(entry.id) ? "Deselect \(entry.hostnames.first ?? "entry")" : "Select \(entry.hostnames.first ?? "entry")")
                            .padding(.leading, 12)
                            .padding(.trailing, 4)
                        }

                        EntryRow(entry: entry, showToggle: !isSelectionMode) {
                            // Toggle enabled (only when not in selection mode)
                            if !isSelectionMode {
                                Task {
                                    try? await store.toggleEntry(entry, in: profile)
                                }
                            } else {
                                toggleSelection(entry)
                            }
                        }
                    }
                    .background(selectedEntries.contains(entry.id) ? Color.blue.opacity(0.1) : Color.clear)
                    .contextMenu {
                        if !isSelectionMode {
                            entryContextMenu(for: entry)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isSelectionMode {
                            toggleSelection(entry)
                        }
                    }

                    if index < visibleEntries.count - 1 {
                        CompactDivider()
                    }
                }

                // Show message if entries are truncated
                if filteredEntries.count > Self.maxVisibleEntries {
                    HStack {
                        Spacer()
                        Text("Use search to find specific entries")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Entry Context Menu

    @ViewBuilder
    private func entryContextMenu(for entry: HostEntry) -> some View {
        Button {
            editingEntry = entry
        } label: {
            Label("Edit", systemImage: SaneIcons.edit)
        }

        Button {
            duplicateEntry(entry)
        } label: {
            Label("Duplicate", systemImage: SaneIcons.duplicate)
        }

        Divider()

        Button {
            Task {
                try? await store.toggleEntry(entry, in: profile)
            }
        } label: {
            Label(entry.isEnabled ? "Disable" : "Enable",
                  systemImage: entry.isEnabled ? SaneIcons.entryDisabled : SaneIcons.entryEnabled)
        }

        Divider()

        Button(role: .destructive) {
            deleteEntry(entry)
        } label: {
            Label("Delete", systemImage: SaneIcons.remove)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        SaneEmptyState(
            icon: SaneIcons.hosts,
            title: "No Entries",
            description: "Add entries using the button above."
        )
    }

    // MARK: - Actions

    private func duplicateEntry(_ entry: HostEntry) {
        let newEntry = HostEntry(
            id: UUID(),
            ipAddress: entry.ipAddress,
            hostnames: entry.hostnames,
            comment: entry.comment,
            isEnabled: entry.isEnabled,
            lineNumber: nil
        )
        Task {
            try? await store.addEntry(newEntry, to: profile)
        }
    }

    private func deleteEntry(_ entry: HostEntry) {
        Task {
            try? await store.removeEntry(entry, from: profile)
        }
    }

    // MARK: - Bulk Actions

    private func toggleSelection(_ entry: HostEntry) {
        if selectedEntries.contains(entry.id) {
            selectedEntries.remove(entry.id)
        } else {
            selectedEntries.insert(entry.id)
        }
    }

    private func bulkEnableSelected() {
        guard licenseService.isPro else {
            proUpsellFeature = .bulkOperations
            return
        }
        Task {
            try? await store.bulkUpdateEntries(ids: selectedEntries, in: profile) { entry in
                entry.isEnabled = true
            }
            selectedEntries.removeAll()
            isSelectionMode = false
        }
    }

    private func bulkDisableSelected() {
        guard licenseService.isPro else {
            proUpsellFeature = .bulkOperations
            return
        }
        Task {
            try? await store.bulkUpdateEntries(ids: selectedEntries, in: profile) { entry in
                entry.isEnabled = false
            }
            selectedEntries.removeAll()
            isSelectionMode = false
        }
    }

    private func bulkDeleteSelected() {
        guard licenseService.isPro else {
            proUpsellFeature = .bulkOperations
            return
        }
        Task {
            try? await store.bulkRemoveEntries(ids: selectedEntries, from: profile)
            selectedEntries.removeAll()
            isSelectionMode = false
        }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
            }

            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(colorScheme == .dark ? color.opacity(0.3) : color.opacity(0.2), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

// MARK: - Entry Row

struct EntryRow: View {
    let entry: HostEntry
    var showToggle: Bool = true
    let onToggle: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            // Enable/Disable toggle (only when showToggle is true)
            if showToggle {
                Button(action: onToggle) {
                    EntryStatusIcon(isEnabled: entry.isEnabled)
                }
                .buttonStyle(.plain)
                .help(entry.isEnabled ? "Disable this entry" : "Enable this entry")
                .accessibilityLabel(entry.isEnabled ? "Disable \(entry.hostnames.first ?? "entry")" : "Enable \(entry.hostnames.first ?? "entry")")
            }

            // IP Address
            IPAddressText(address: entry.ipAddress, isEnabled: entry.isEnabled)
                .frame(width: 120, alignment: .leading)

            // Hostnames
            VStack(alignment: .leading, spacing: 2) {
                HostnameText(hostname: entry.primaryHostname, isEnabled: entry.isEnabled, isPrimary: true)

                if entry.hostnames.count > 1 {
                    Text(entry.hostnames.dropFirst().joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Comment
            if let comment = entry.comment {
                Text(comment)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(maxWidth: 150, alignment: .trailing)
            }

            // System badge
            if entry.isSystemEntry {
                StatusBadge("System", color: .secondary, icon: SaneIcons.lock)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(isHovering ? Color.primary.opacity(0.03) : Color.clear)
        .onHover { isHovering = $0 }
        .opacity(entry.isEnabled ? 1 : 0.6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.ipAddress) \(entry.hostnames.joined(separator: ", ")), \(entry.isEnabled ? "enabled" : "disabled")")
    }
}

// MARK: - Add Entry Sheet

struct AddEntrySheet: View {
    let store: ProfileStore
    let profile: Profile

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var ipAddress = "127.0.0.1"
    @State private var hostname = ""
    @State private var comment = ""
    @State private var isValid = false

    private let parser = HostsParser()

    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Image(systemName: SaneIcons.add)
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("Add Entry")
                    .font(.headline)
            }

            // Form
            VStack(spacing: 16) {
                CompactSection("IP Address", icon: SaneIcons.network, iconColor: .blue) {
                    TextField("127.0.0.1", text: $ipAddress)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }

                CompactSection("Hostname", icon: SaneIcons.globe, iconColor: .blue) {
                    TextField("example.local", text: $hostname)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }

                CompactSection("Comment (optional)", icon: "text.quote", iconColor: .secondary) {
                    TextField("Block ads", text: $comment)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
            }

            if !isValid, !hostname.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: SaneIcons.warning)
                    Text("Invalid IP address or hostname")
                }
                .font(.caption)
                .foregroundStyle(.red)
            }

            // Actions
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)

                Button("Add Entry") {
                    addEntry()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.saneAccent)
                .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 380)
        .background(SaneGradientBackground())
        .onChange(of: ipAddress) { validate() }
        .onChange(of: hostname) { validate() }
    }

    private func validate() {
        isValid = parser.isValidIPAddress(ipAddress) && parser.isValidHostname(hostname)
    }

    private func addEntry() {
        // Strip newlines from comment to prevent hosts file format corruption
        let sanitizedComment = comment.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespaces)

        let entry = HostEntry(
            ipAddress: ipAddress,
            hostnames: hostname.split(separator: " ").map(String.init),
            comment: sanitizedComment.isEmpty ? nil : sanitizedComment
        )

        Task {
            try? await store.addEntry(entry, to: profile)
            dismiss()
        }
    }
}

// MARK: - Edit Entry Sheet

struct EditEntrySheet: View {
    let store: ProfileStore
    let profile: Profile
    let entry: HostEntry

    @Environment(\.dismiss) private var dismiss
    @State private var ipAddress: String
    @State private var hostname: String
    @State private var comment: String
    @State private var isValid = true

    private let parser = HostsParser()

    init(store: ProfileStore, profile: Profile, entry: HostEntry) {
        self.store = store
        self.profile = profile
        self.entry = entry
        _ipAddress = State(initialValue: entry.ipAddress)
        _hostname = State(initialValue: entry.hostnames.joined(separator: " "))
        _comment = State(initialValue: entry.comment ?? "")
    }

    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Image(systemName: SaneIcons.edit)
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("Edit Entry")
                    .font(.headline)
            }

            // Form
            VStack(spacing: 16) {
                CompactSection("IP Address", icon: SaneIcons.network, iconColor: .blue) {
                    TextField("127.0.0.1", text: $ipAddress)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }

                CompactSection("Hostname", icon: SaneIcons.globe, iconColor: .blue) {
                    TextField("example.local", text: $hostname)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }

                CompactSection("Comment (optional)", icon: "text.quote", iconColor: .secondary) {
                    TextField("Block ads", text: $comment)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
            }

            if !isValid {
                HStack(spacing: 4) {
                    Image(systemName: SaneIcons.warning)
                    Text("Invalid IP address or hostname")
                }
                .font(.caption)
                .foregroundStyle(.red)
            }

            // Actions
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)

                Button("Save") {
                    saveEntry()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.saneAccent)
                .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 380)
        .background(SaneGradientBackground())
        .onChange(of: ipAddress) { validate() }
        .onChange(of: hostname) { validate() }
    }

    private func validate() {
        isValid = parser.isValidIPAddress(ipAddress) && !hostname.isEmpty
    }

    private func saveEntry() {
        // Strip newlines from comment to prevent hosts file format corruption
        let sanitizedComment = comment.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespaces)

        var updated = entry
        updated.ipAddress = ipAddress
        updated.hostnames = hostname.split(separator: " ").map(String.init)
        updated.comment = sanitizedComment.isEmpty ? nil : sanitizedComment

        Task {
            try? await store.updateEntry(updated, in: profile)
            dismiss()
        }
    }
}

// MARK: - Freshness Indicator

struct FreshnessIndicator: View {
    let date: Date

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(freshnessColor)
                .frame(width: 8, height: 8)
            Text(freshnessLabel)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(freshnessColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(freshnessColor.opacity(0.2))
        .clipShape(Capsule())
        .accessibilityLabel("Source freshness: \(freshnessLabel)")
    }

    private var freshnessColor: Color {
        let hours = Date().timeIntervalSince(date) / 3600
        if hours < 24 { return .blue } // Fresh - blue to differentiate from Active green
        if hours < 168 { return .orange } // 7 days
        return .red
    }

    private var freshnessLabel: String {
        let hours = Date().timeIntervalSince(date) / 3600
        if hours < 24 { return "Fresh" }
        if hours < 168 { return "Aging" }
        return "Stale"
    }
}
