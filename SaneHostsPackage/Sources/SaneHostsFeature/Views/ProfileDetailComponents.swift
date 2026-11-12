import SaneUI
import SwiftUI

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
                    .foregroundColor(.white)
            }

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .fontWeight(.medium)
                .foregroundColor(.white)
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
            if showToggle {
                Button(action: onToggle) {
                    EntryStatusIcon(isEnabled: entry.isEnabled)
                }
                .buttonStyle(.plain)
                .help(entry.isEnabled ? "Disable this entry" : "Enable this entry")
                .accessibilityLabel(entry.isEnabled ? "Disable \(entry.hostnames.first ?? "entry")" : "Enable \(entry.hostnames.first ?? "entry")")
            }

            IPAddressText(address: entry.ipAddress, isEnabled: entry.isEnabled)
                .frame(width: 140, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HostnameText(hostname: entry.primaryHostname, isEnabled: entry.isEnabled, isPrimary: true)

                if entry.hostnames.count > 1 {
                    Text(entry.hostnames.dropFirst().joined(separator: ", "))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let comment = entry.comment {
                Text(comment)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(maxWidth: 150, alignment: .trailing)
            }

            if entry.isSystemEntry {
                StatusBadge("System", color: .saneAccent, icon: SaneIcons.lock)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(isHovering ? Color.primary.opacity(0.03) : Color.clear)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(entry.ipAddress) \(entry.hostnames.joined(separator: ", ")), \(entry.isEnabled ? "enabled" : "disabled")")
        .accessibilityIdentifier("entry-row-\(entry.hostnames.first ?? "entry")")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Add Entry Sheet

struct AddEntrySheet: View {
    let store: ProfileStore
    let profile: Profile

    @Environment(\.dismiss) private var dismiss
    @State private var ipAddress = "127.0.0.1"
    @State private var hostname = ""
    @State private var comment = ""
    @State private var isValid = false

    private let parser = HostsParser()

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Image(systemName: SaneIcons.add)
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("Add Entry")
                    .font(.headline)
            }

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
                        .accessibilityLabel("Hostname")
                        .accessibilityIdentifier("add-entry-hostname")
                }

                CompactSection("Comment (optional)", icon: "text.quote", iconColor: .saneAccent) {
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
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(SaneActionButtonStyle())

                Button("Add Entry") {
                    addEntry()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(SaneActionButtonStyle(prominent: true))
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
        isValid = parser.isValidIPAddress(ipAddress) && hostnamesAreValid(hostname)
    }

    private func addEntry() {
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

    private func hostnamesAreValid(_ value: String) -> Bool {
        let hosts = value.split { $0.isWhitespace }.map(String.init)
        return !hosts.isEmpty && hosts.allSatisfy { parser.isValidHostname($0) }
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
            HStack {
                Image(systemName: SaneIcons.edit)
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("Edit Entry")
                    .font(.headline)
            }

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
                        .accessibilityLabel("Hostname")
                        .accessibilityIdentifier("edit-entry-hostname")
                }

                CompactSection("Comment (optional)", icon: "text.quote", iconColor: .saneAccent) {
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
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(SaneActionButtonStyle())

                Button("Save") {
                    saveEntry()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(SaneActionButtonStyle(prominent: true))
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
        isValid = parser.isValidIPAddress(ipAddress) && hostnamesAreValid(hostname)
    }

    private func saveEntry() {
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

    private func hostnamesAreValid(_ value: String) -> Bool {
        let hosts = value.split { $0.isWhitespace }.map(String.init)
        return !hosts.isEmpty && hosts.allSatisfy { parser.isValidHostname($0) }
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
                .font(.system(size: 13, weight: .semibold))
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(freshnessColor.opacity(0.2))
        .clipShape(Capsule())
        .accessibilityLabel("Source freshness: \(freshnessLabel)")
    }

    private var freshnessColor: Color {
        let hours = Date().timeIntervalSince(date) / 3600
        if hours < 24 {
            return .blue
        }
        if hours < 168 {
            return .orange
        }
        return .red
    }

    private var freshnessLabel: String {
        let hours = Date().timeIntervalSince(date) / 3600
        if hours < 24 {
            return "Fresh"
        }
        if hours < 168 {
            return "Aging"
        }
        return "Stale"
    }
}

// MARK: - Detail Notice

struct DetailNotice: Equatable {
    enum Style: Equatable {
        case success
        case warning
        case error
    }

    let id = UUID()
    let style: Style
    let text: String

    static func success(_ text: String) -> DetailNotice {
        DetailNotice(style: .success, text: text)
    }

    static func warning(_ text: String) -> DetailNotice {
        DetailNotice(style: .warning, text: text)
    }

    static func error(_ text: String) -> DetailNotice {
        DetailNotice(style: .error, text: text)
    }
}

struct DetailNoticeBanner: View {
    let notice: DetailNotice
    let onDismiss: () -> Void

    private var tint: Color {
        switch notice.style {
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }

    private var icon: String {
        switch notice.style {
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(tint)
            Text(notice.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .accessibilityLabel("Dismiss message")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(tint.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(tint.opacity(0.45), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}
