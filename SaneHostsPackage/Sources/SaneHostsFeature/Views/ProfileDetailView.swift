import SaneUI
import SwiftUI

struct ProfileDetailView: View {
    @AppStorage(ProtectionLock.enabledKey) private var protectionLocked = false
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

    @State private var isSelectionMode = false
    @State private var selectedEntries: Set<UUID> = []
    @State private var proUpsellFeature: ProFeature?
    @State private var isUpdatingLists = false
    @State private var notice: DetailNotice?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                profileHeaderCard

                if let notice {
                    DetailNoticeBanner(notice: notice) {
                        withAnimation { self.notice = nil }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                statsRow

                if isSelectionMode {
                    bulkActionsBar
                }

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
            searchDebounceTask?.cancel()
            if newValue.isEmpty {
                debouncedSearchText = ""
                return
            }
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
        .onChange(of: profile.id) { _, _ in
            notice = nil
        }
    }

    // MARK: - Computed

    private var filteredEntries: [HostEntry] {
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
                HStack {
                    ProfileColorDot(color: profile.colorTag)

                    if profile.isActive {
                        StatusBadge("Active", color: .saneSuccess, icon: SaneIcons.success)
                            .accessibilityLabel("Profile status: Active")
                    } else {
                        StatusBadge("Inactive", color: .profileInactive, icon: SaneIcons.profileInactive)
                            .accessibilityLabel("Profile status: Inactive")
                    }

                    Spacer()

                    if profile.isActive {
                        Button {
                            onDeactivate()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: SaneIcons.deactivate)
                                Text(ProtectionUXCopy.turnOffActionTitle)
                            }
                        }
                        .buttonStyle(SaneActionButtonStyle(destructive: true))
                        .accessibilityLabel(ProtectionUXCopy.turnOffActionTitle)
                        .accessibilityHint("Removes this profile’s rules while leaving standard hosts entries")
                    } else {
                        Button {
                            onActivate()
                            if TutorialState.shared.currentStep == .activateProfile {
                                TutorialState.shared.completeTutorial()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: SaneIcons.activate)
                                Text("Activate")
                            }
                        }
                        .buttonStyle(SaneActionButtonStyle(prominent: true))
                        .activateButtonAnchor()
                        .accessibilityLabel("Activate profile")
                        .accessibilityHint("Double-tap to activate this profile")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                if profile.isActive {
                    CompactDivider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text(ProtectionUXCopy.activePersistence)
                        Text(ProtectionUXCopy.authenticationRequirement(locked: protectionLocked))
                        Text(ProtectionUXCopy.deactivationImpact)
                    }
                    .font(.callout)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                }

                CompactDivider()

                CompactRow("Source", icon: sourceIcon, iconColor: .saneAccent) {
                    Text(profile.source.displayName)
                        .foregroundColor(.white)
                }

                CompactDivider()

                CompactRow("Modified", icon: "clock", iconColor: .saneAccent) {
                    Text(profile.modifiedAt, style: .relative)
                        .foregroundColor(.white)
                }

                if case let .remote(url, _) = profile.source {
                    CompactDivider()
                    CompactRow(url.isFileURL ? "Source File" : "Source URL", icon: url.isFileURL ? "doc" : "link", iconColor: .blue) {
                        Text(url.isFileURL ? url.lastPathComponent : (url.host ?? url.absoluteString))
                            .font(.body)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(url.isFileURL ? url.path : url.absoluteString)
                    }
                }

                if BlocklistUpdater.canUpdate(profile) {
                    CompactDivider()
                    listsRow
                }
            }
        }
    }

    private var listsRow: some View {
        let lastUpdated = BlocklistUpdater.lastUpdated(profile)
        return HStack(spacing: 8) {
            Image(systemName: isUpdatingLists ? "arrow.triangle.2.circlepath" : freshnessIcon(for: lastUpdated))
                .font(.body)
                .foregroundStyle(isUpdatingLists ? Color.saneAccent : freshnessColor(for: lastUpdated))
                .frame(width: 20)
            Text("Lists")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)

            Spacer(minLength: 12)

            Group {
                if isUpdatingLists {
                    ProgressView()
                        .controlSize(.small)
                    Text("Updating…")
                } else if let lastUpdated {
                    Text("Updated \(lastUpdated.formatted(.relative(presentation: .named)))")
                    FreshnessIndicator(date: lastUpdated)
                } else {
                    Text("Not updated since import")
                }
            }
            .font(.body)
            .foregroundColor(.white)
            .lineLimit(1)

            Button {
                updateLists()
            } label: {
                Label("Update Now", systemImage: "arrow.down.circle")
            }
            .buttonStyle(SaneActionButtonStyle(compact: true))
            .disabled(isUpdatingLists)
            .help("Download the latest version of this profile’s blocklists")
            .accessibilityLabel("Update lists now")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Freshness

    private func freshnessIcon(for date: Date?) -> String {
        guard let date else { return "exclamationmark.circle" }
        let hours = Date().timeIntervalSince(date) / 3600
        if hours < 24 {
            return "checkmark.circle"
        }
        if hours < 168 {
            return "clock"
        } // 7 days
        return "exclamationmark.triangle"
    }

    private func freshnessColor(for date: Date?) -> Color {
        guard let date else { return .orange }
        let hours = Date().timeIntervalSince(date) / 3600
        if hours < 24 {
            return .blue
        } // Fresh - use blue to differentiate from Active green
        if hours < 168 {
            return .saneAccent
        } // 7 days
        return .orange
    }

    private var sourceIcon: String {
        switch profile.source {
        case .local: SaneIcons.profileLocal
        case let .remote(url, _): url.isFileURL ? "doc" : SaneIcons.profileRemote
        case .merged: "arrow.triangle.merge"
        case .system: SaneIcons.profileSystem
        }
    }

    // MARK: - Stats Row

    private func compactNumber(_ n: Int) -> String {
        n.formatted(.number.notation(.compactName))
    }

    private var statsRow: some View {
        let counts = profile.entryCounts
        return HStack(spacing: 16) {
            StatCard(
                title: "Total",
                value: compactNumber(profile.entryCount),
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
                color: .saneWarning
            )

            Button {
                showingAddEntry = true
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title)
                        .foregroundStyle(.orange)
                    Text("Add Entry")
                        .font(.system(size: 13, weight: .semibold))
                        .fontWeight(.medium)
                        .foregroundColor(.white)
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
        HStack(spacing: 8) {
            Text("\(selectedEntries.count) selected")
                .font(.system(size: 13, weight: .semibold))
                .fontWeight(.medium)
                .foregroundColor(.white)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)

            Spacer(minLength: 4)

            Button {
                if selectedEntries.count == filteredEntries.count {
                    selectedEntries.removeAll()
                } else {
                    selectedEntries = Set(filteredEntries.map(\.id))
                }
            } label: {
                Text(selectedEntries.count == filteredEntries.count ? "Deselect All" : "Select All")
            }
            .buttonStyle(SaneActionButtonStyle(compact: true))
            .accessibilityLabel(selectedEntries.count == filteredEntries.count ? "Deselect all entries" : "Select all entries")

            Divider()
                .frame(height: 20)

            Button {
                bulkEnableSelected()
            } label: {
                Label("Enable", systemImage: SaneIcons.entryEnabled)
            }
            .buttonStyle(SaneActionButtonStyle(compact: true))
            .disabled(selectedEntries.isEmpty)
            .accessibilityLabel("Enable selected entries")

            Button {
                bulkDisableSelected()
            } label: {
                Label("Disable", systemImage: SaneIcons.entryDisabled)
            }
            .buttonStyle(SaneActionButtonStyle(compact: true))
            .disabled(selectedEntries.isEmpty)
            .accessibilityLabel("Disable selected entries")

            Button(role: .destructive) {
                bulkDeleteSelected()
            } label: {
                Label("Delete", systemImage: SaneIcons.remove)
            }
            .buttonStyle(SaneActionButtonStyle(destructive: true, compact: true))
            .disabled(selectedEntries.isEmpty)
            .accessibilityLabel("Delete selected entries")

            Divider()
                .frame(height: 20)

            Button("Done") {
                isSelectionMode = false
                selectedEntries.removeAll()
            }
            .buttonStyle(SaneActionButtonStyle(prominent: true, compact: true))
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

    /// Rendering more rows than this freezes the UI on 100K+ entry profiles.
    private static let maxVisibleEntries = 100

    private var entriesSection: some View {
        CompactSection("Entries", icon: SaneIcons.hosts, iconColor: .saneAccent) {
            let matchingEntries = filteredEntries
            let matchingCount = matchingEntries.count
            VStack(spacing: 0) {
                HStack {
                    if profile.hasPartialEntries, debouncedSearchText.isEmpty {
                        Text("Showing \(compactNumber(profile.entries.count)) of \(compactNumber(profile.entryCount)) entries")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                    } else if matchingCount > Self.maxVisibleEntries {
                        Text("Showing \(compactNumber(min(matchingCount, Self.maxVisibleEntries))) of \(compactNumber(matchingCount)) entries")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                    } else {
                        Text(matchingCount == 1 ? "1 entry" : "\(compactNumber(matchingCount)) entries")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                    }
                    Spacer()

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
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.teal)
                                }
                            }
                        }
                        .buttonStyle(SaneActionButtonStyle(compact: true))
                        .help(licenseService.isPro ? "Select entries for bulk enable, disable, or delete" : "Bulk operations require paid access")
                        .accessibilityLabel(licenseService.isPro ? "Enter selection mode" : "Bulk operations — paid feature")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                CompactDivider()

                if profile.hasPartialEntries, !debouncedSearchText.isEmpty {
                    HStack {
                        Spacer()
                        Text("Searching the loaded preview for this very large profile")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.vertical, 12)
                        Spacer()
                    }
                }

                let visibleEntries = Array(matchingEntries.prefix(Self.maxVisibleEntries))
                ForEach(Array(visibleEntries.enumerated()), id: \.element.id) { index, entry in
                    HStack(spacing: 0) {
                        if isSelectionMode {
                            Button {
                                toggleSelection(entry)
                            } label: {
                                Image(systemName: selectedEntries.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .foregroundStyle(selectedEntries.contains(entry.id) ? .blue : .white)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(selectedEntries.contains(entry.id) ? "Deselect \(entry.hostnames.first ?? "entry")" : "Select \(entry.hostnames.first ?? "entry")")
                            .padding(.leading, 12)
                            .padding(.trailing, 4)
                        }

                        EntryRow(entry: entry, showToggle: !isSelectionMode) {
                            if !isSelectionMode {
                                Task {
                                    try? await store.toggleEntry(entry, in: profile)
                                }
                            } else {
                                toggleSelection(entry)
                            }
                        }
                        .contextMenu {
                            if !isSelectionMode {
                                entryContextMenu(for: entry)
                            }
                        }
                    }
                    .background(selectedEntries.contains(entry.id) ? Color.blue.opacity(0.1) : Color.clear)
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

                if matchingCount > Self.maxVisibleEntries {
                    HStack {
                        Spacer()
                        Text("Use search to find specific entries")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
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

        let allowable = allowableHostnames(in: entry)
        if allowable.count == 1, let hostname = allowable.first {
            Button {
                alwaysAllow(hostname)
            } label: {
                Label("Always Allow \(hostname)", systemImage: "checkmark.shield")
            }
        } else if allowable.count > 1 {
            Menu {
                ForEach(allowable, id: \.self) { hostname in
                    Button(hostname) { alwaysAllow(hostname) }
                }
            } label: {
                Label("Always Allow", systemImage: "checkmark.shield")
            }
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

    // MARK: - Allowlist and Lists

    private func allowableHostnames(in entry: HostEntry) -> [String] {
        guard HostAllowlist.blockingAddresses.contains(entry.ipAddress) else { return [] }
        let allowlist = AllowlistStore.shared.allowlist
        return entry.hostnames.filter {
            !HostsParser.reservedHostnames.contains($0.lowercased()) && !allowlist.allows($0)
        }
    }

    private func alwaysAllow(_ hostname: String) {
        Task {
            guard await ProtectionLock.authorize("allow \(hostname)") else { return }
            var allowlist = AllowlistStore.shared.allowlist
            guard allowlist.add(hostname) else { return }
            do {
                try AllowlistStore.shared.replace(with: allowlist)
            } catch {
                show(.error("Couldn’t save allowed sites: \(error.localizedDescription)"))
                return
            }
            guard profile.isActive else {
                show(.success("\(hostname) will stay unblocked when protection is on."))
                return
            }
            do {
                let warning = try await ProtectionController.reapplyActiveProfile(requireUnlock: false)
                show(warning.map(DetailNotice.warning) ?? .success("\(hostname) is no longer blocked."))
            } catch {
                if let message = HostsServiceError.actionErrorMessage(for: error, action: "\(hostname) was added to Allowed Sites, but couldn’t be applied") {
                    show(.error(message))
                }
            }
        }
    }

    private func updateLists() {
        guard !isUpdatingLists else { return }
        isUpdatingLists = true
        notice = nil
        let target = profile
        Task {
            defer { isUpdatingLists = false }
            do {
                let result = try await BlocklistUpdater.update(target, store: store)
                if let warning = result.warning {
                    show(.warning(warning))
                } else if result.didChange {
                    let delta = result.newCount - result.previousCount
                    let change = delta == 0 ? "" : (delta > 0 ? " (\(delta.formatted()) added)" : " (\((-delta).formatted()) removed)")
                    show(.success("Lists updated: \(result.newCount.formatted()) entries\(change)."))
                } else {
                    show(.success("Lists are already up to date."))
                }
            } catch {
                if let message = HostsServiceError.actionErrorMessage(for: error, action: "Couldn’t update lists") {
                    show(.error(message))
                }
            }
        }
    }

    private func show(_ newNotice: DetailNotice) {
        withAnimation { notice = newNotice }
        guard newNotice.style == .success else { return }
        let shown = newNotice
        Task {
            try? await Task.sleep(for: .seconds(6))
            if notice == shown {
                withAnimation { notice = nil }
            }
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
