import SwiftUI
import AppKit

// MARK: - Notifications

public extension Notification.Name {
    static let showNewProfileSheet = Notification.Name("showNewProfileSheet")
    static let showImportSheet = Notification.Name("showImportSheet")
}

// MARK: - Visual Effect Blur (NSVisualEffectView wrapper)

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Gradient Backgrounds

struct SaneGradientBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                // Dark mode: beautiful glass effect
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)

                // Subtle teal/blue tint (hosts/network theme)
                LinearGradient(
                    colors: [
                        Color.saneAccent.opacity(0.08),
                        Color.blue.opacity(0.05),
                        Color.saneAccent.opacity(0.03)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                // Light mode: soft, warm gradient
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.98, blue: 0.99),
                        Color(red: 0.92, green: 0.96, blue: 0.98),
                        Color(red: 0.94, green: 0.97, blue: 0.99)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Compact Section

struct CompactSection<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let icon: String?
    let iconColor: Color
    let content: Content

    init(
        _ title: String,
        icon: String? = nil,
        iconColor: Color = .secondary,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(iconColor)
                }
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .padding(.leading, 4)

            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .dark
                        ? Color.white.opacity(0.08)
                        : Color.white)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(colorScheme == .dark ? .ultraThinMaterial : .regularMaterial)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(colorScheme == .dark
                        ? Color.white.opacity(0.12)
                        : Color.saneAccent.opacity(0.15), lineWidth: 1)
            )
            .shadow(
                color: colorScheme == .dark ? .black.opacity(0.15) : .saneAccent.opacity(0.08),
                radius: colorScheme == .dark ? 8 : 6,
                x: 0,
                y: 3
            )
            .padding(.horizontal, 2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

// MARK: - Compact Row

struct CompactRow<Content: View>: View {
    let label: String
    let icon: String?
    let iconColor: Color
    let content: Content

    init(
        _ label: String,
        icon: String? = nil,
        iconColor: Color = .secondary,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.icon = icon
        self.iconColor = iconColor
        self.content = content()
    }

    var body: some View {
        HStack {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(iconColor)
                    .frame(width: 20)
            }
            Text(label)
            Spacer()
            content
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Compact Toggle

struct CompactToggle: View {
    let label: String
    let icon: String?
    let iconColor: Color
    @Binding var isOn: Bool

    init(
        label: String,
        icon: String? = nil,
        iconColor: Color = .secondary,
        isOn: Binding<Bool>
    ) {
        self.label = label
        self.icon = icon
        self.iconColor = iconColor
        self._isOn = isOn
    }

    var body: some View {
        HStack {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(iconColor)
                    .frame(width: 20)
            }
            Text(label)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(isOn ? "on" : "off")")
    }
}

// MARK: - Compact Divider

struct CompactDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 12)
    }
}

// MARK: - Glass Group Box Style

struct GlassGroupBoxStyle: GroupBoxStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            configuration.label
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            configuration.content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? .thickMaterial : .regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? .white.opacity(0.1) : .black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 4, y: 2)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let text: String
    let color: Color
    let icon: String?

    init(_ text: String, color: Color, icon: String? = nil) {
        self.text = text
        self.color = color
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.caption2)
            }
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(text) status")
    }
}

// MARK: - Profile Color Dot

struct ProfileColorDot: View {
    let color: ProfileColor

    var body: some View {
        Circle()
            .fill(swiftUIColor)
            .frame(width: 10, height: 10)
            .accessibilityLabel("\(color.rawValue) color tag")
    }

    private var swiftUIColor: Color {
        switch color {
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

// MARK: - Action Button

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .fontWeight(.medium)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
        .controlSize(.regular)
    }
}

// MARK: - Entry Status Icon

struct EntryStatusIcon: View {
    let isEnabled: Bool

    var body: some View {
        Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
            .font(.body)
            .foregroundStyle(isEnabled ? .green : .secondary)
    }
}

// MARK: - IP Address Text

struct IPAddressText: View {
    let address: String
    let isEnabled: Bool

    var body: some View {
        Text(address)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(isEnabled ? .primary : .secondary)
    }
}

// MARK: - Hostname Text

struct HostnameText: View {
    let hostname: String
    let isEnabled: Bool
    let isPrimary: Bool

    var body: some View {
        Text(hostname)
            .fontWeight(isPrimary ? .medium : .regular)
            .foregroundStyle(isEnabled ? (isPrimary ? .primary : .secondary) : .tertiary)
    }
}

// MARK: - Empty State View

struct SaneEmptyState: View {
    let icon: String
    let title: String
    let description: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        icon: String,
        title: String,
        description: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.description = description
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            VStack(spacing: 8) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle = actionTitle, let action = action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(40)
    }
}

// MARK: - Loading Overlay

struct LoadingOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)

                Text(message)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .padding(32)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - Semantic Icons

/// Hosts-specific SF Symbols with semantic meaning
enum SaneIcons {
    // Navigation & Structure
    static let profiles = "folder.fill"
    static let settings = "gear"
    static let about = "info.circle"

    // Profile States
    static let profileActive = "checkmark.circle.fill"
    static let profileInactive = "circle"
    static let profileLocal = "folder"
    static let profileRemote = "cloud"
    static let profileSystem = "lock.shield"

    // Actions
    static let activate = "power"
    static let deactivate = "power.circle"
    static let add = "plus"
    static let remove = "trash"
    static let edit = "pencil"
    static let duplicate = "doc.on.doc"
    static let export = "square.and.arrow.up"
    static let import_ = "square.and.arrow.down"
    static let refresh = "arrow.clockwise"
    static let sync = "arrow.triangle.2.circlepath"

    // Entry States
    static let entryEnabled = "checkmark.circle.fill"
    static let entryDisabled = "circle"
    static let entrySystem = "lock.fill"

    // Network & DNS
    static let network = "network"
    static let dns = "server.rack"
    static let hosts = "doc.text"
    static let globe = "globe"
    static let localhost = "house"

    // Status
    static let success = "checkmark.circle.fill"
    static let error = "exclamationmark.triangle.fill"
    static let warning = "exclamationmark.circle.fill"
    static let info = "info.circle.fill"

    // Security
    static let shield = "shield.fill"
    static let lock = "lock.fill"
    static let unlock = "lock.open.fill"

    // Templates
    static let templateAdBlock = "hand.raised.slash"
    static let templateDev = "hammer"
    static let templateSocial = "bubble.left.and.bubble.right"
    static let templatePrivacy = "eye.slash"
}

// MARK: - Semantic Colors

extension Color {
    static let saneAccent = Color(red: 0.373, green: 0.659, blue: 0.827) // Shield Teal #5fa8d3
    static let saneSuccess = Color.green
    static let saneWarning = Color.orange
    static let saneError = Color.red
    static let saneInfo = Color.blue

    // Profile colors
    static let profileActive = Color.green
    static let profileInactive = Color.secondary
}
