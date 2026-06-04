import AppKit
import SaneUI
import SwiftUI
import UniformTypeIdentifiers

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
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
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
                                    .foregroundStyle(selectedProfiles.contains(profile.id) ? .purple : .white)

                                ProfileColorDot(color: profile.colorTag)

                                Text(profile.name)
                                    .font(.body)
                                    .foregroundColor(.white)

                                Spacer()

                                Text("\(profile.entryCount.formatted(.number.notation(.compactName))) entries")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedProfiles.contains(profile.id) ? Color.purple.opacity(0.1) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(selectedProfiles.contains(profile.id) ? "Deselect" : "Select") \(profile.name)")
                        .accessibilityHint("\(profile.entryCount) entries")
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
                let totalEntries = store.profiles.filter { selectedProfiles.contains($0.id) }.reduce(0) { $0 + $1.entryCount }
                Text("Will combine ~\(totalEntries) entries (duplicates removed)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
            }

            if let error {
                Text(error)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
            }

            // Actions
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(SaneActionButtonStyle())

                Button("Merge") {
                    mergeProfiles()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(SaneActionButtonStyle(prominent: true))
                .disabled(selectedProfiles.count < 2 || mergedName.isEmpty || isMerging)
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(SaneGradientBackground())
        .onAppear {
            // Auto-fill name on appear if profiles are preselected
            if !selectedProfiles.isEmpty, mergedName.isEmpty {
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
