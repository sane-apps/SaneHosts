import AppKit
import SaneUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Preset Row View

struct PresetRowView: View {
    let preset: ProfilePreset
    let isSelected: Bool
    let showLock: Bool
    let onLockedTap: (() -> Void)?

    private var presetColor: Color {
        preset.colorTag.uiColor
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: preset.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(presetColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(preset.displayName)
                    .font(.body)
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(preset.tagline)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }

            Spacer()

            if showLock {
                Button {
                    onLockedTap?()
                } label: {
                    ProLockBadge()
                }
                .buttonStyle(.plain)
                .help("Locked feature: \(preset.tagline)")
            } else {
                Image(systemName: "icloud.and.arrow.down")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
            }
        }
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Preset Detail View

struct PresetDetailView: View {
    let preset: ProfilePreset
    let isDownloading: Bool
    let onDownload: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var presetColor: Color {
        preset.colorTag.uiColor
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: preset.icon)
                        .font(.system(size: 64))
                        .foregroundStyle(presetColor)

                    VStack(spacing: 6) {
                        Text(preset.displayName)
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text(preset.tagline)
                            .font(.title3)
                            .foregroundColor(.white)
                    }
                }
                .padding(.top, 40)

                // Description
                Text(preset.description)
                    .font(.body)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)

                // Stats
                HStack(spacing: 32) {
                    VStack(spacing: 4) {
                        Text(preset.estimatedEntries)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        Text("Blocked domains")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                    }

                    VStack(spacing: 4) {
                        Text("\(preset.blocklistSourceIds.count)")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        Text("Blocklists")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                    }
                }

                // Blocklist sources included
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Includes")
                            .font(.system(size: 13, weight: .semibold))
                            .fontWeight(.medium)
                            .foregroundColor(.white)

                        ForEach(preset.blocklistSources, id: \.id) { source in
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(presetColor)
                                Text(source.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                Spacer()
                            }
                        }
                    }
                    .padding(4)
                }
                .frame(maxWidth: 400)

                // Download button
                Button {
                    onDownload()
                } label: {
                    HStack(spacing: 8) {
                        if isDownloading {
                            ProgressView()
                                .controlSize(.small)
                            Text("Downloading blocklists...")
                        } else {
                            Image(systemName: "icloud.and.arrow.down")
                            Text("Add \(preset.displayName)")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: 280)
                    .padding(.vertical, 12)
                }
                .buttonStyle(SaneActionButtonStyle(prominent: true))
                .disabled(isDownloading)
                .accessibilityLabel(isDownloading ? "Downloading blocklists" : "Add \(preset.displayName)")

                Spacer()
            }
            .padding(.horizontal, 40)
        }
    }
}

#Preview {
    MainView()
}
