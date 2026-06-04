import AppKit
import SaneUI
import SwiftUI
import UniformTypeIdentifiers

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
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}

// MARK: - Pro-Gated Quick Action Button

/// Quick action button with optional Pro lock badge overlay.
/// When `isPro` is false, shows a teal lock badge after the subtitle.
struct ProGatedQuickActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let isPro: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(isPro ? color : .white)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if !isPro {
                    ProLockBadge()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .accessibilityLabel(title)
        .accessibilityHint(isPro ? subtitle : "\(subtitle) — Pro feature")
    }
}

// MARK: - Pro Lock Badge

/// Teal lock + "Pro" badge used on gated actions.
struct ProLockBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.system(size: 13, weight: .semibold))
            Text("Pro")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.teal.opacity(0.28))
        .clipShape(Capsule())
    }
}

// MARK: - Profile Row

struct ProfileRowView: View {
    let profile: Profile

    var body: some View {
        HStack(spacing: 12) {
            // Semantic color based on source type (remote=accent, merged=indigo, local=gray)
            ProfileColorDot(color: profile.source.semanticColor)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(profile.name)
                        .font(.body)
                        .fontWeight(profile.isActive ? .semibold : .regular)
                        .foregroundColor(.white)
                        .lineLimit(1)

                    // Source indicator icon
                    if profile.source.isRemote {
                        Image(systemName: SaneIcons.profileRemote)
                            .font(.subheadline)
                            .foregroundStyle(Color.saneAccent)
                    } else if profile.source.isMerged {
                        Image(systemName: "arrow.triangle.merge")
                            .font(.subheadline)
                            .foregroundStyle(.indigo)
                    }
                }

                Text(entrySummary)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
            }

            Spacer()

            if profile.isActive {
                StatusBadge("Active", color: .saneSuccess, icon: SaneIcons.success)
            }
        }
        .padding(.vertical, 5)
    }

    private var entrySummary: String {
        let count = profile.entryCount
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

    @Environment(\.colorScheme) private var colorScheme

    private var totalEntries: Int {
        profiles.reduce(0) { $0 + $1.entryCount }
    }

    private var hasActiveProfile: Bool {
        profiles.contains(where: \.isActive)
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
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
            }

            // Selected profiles list
            VStack(alignment: .leading, spacing: 10) {
                Text("Selected")
                    .font(.system(size: 13, weight: .semibold))
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.leading, 4)

                VStack(spacing: 0) {
                    ForEach(profiles) { profile in
                        HStack(spacing: 10) {
                            ProfileColorDot(color: profile.source.semanticColor)

                            Text(profile.name)
                                .foregroundColor(.white)
                                .lineLimit(1)

                            Spacer()

                            if profile.isActive {
                                StatusBadge("Active", color: .saneSuccess, icon: SaneIcons.success)
                            }

                            Text(profile.entryCount.formatted(.number.notation(.compactName)))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
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
                .buttonStyle(SaneActionButtonStyle(prominent: true))
                .accessibilityLabel("Merge into new profile")

                HStack(spacing: 12) {
                    // Export
                    Button(action: onExport) {
                        HStack {
                            Image(systemName: SaneIcons.export)
                            Text("Export All")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SaneActionButtonStyle())
                    .accessibilityLabel("Export all selected profiles")
                }

                // Delete
                Button(role: .destructive, action: onDelete) {
                    HStack {
                        Image(systemName: SaneIcons.remove)
                        Text("Delete Selected")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SaneActionButtonStyle(destructive: true))
                .disabled(hasActiveProfile)
                .accessibilityLabel("Delete selected profiles")

                if hasActiveProfile {
                    Text("Cannot delete active profiles")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
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
