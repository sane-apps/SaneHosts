import SwiftUI
import SaneHostsFeature
import ServiceManagement
import Sparkle
import os

// MARK: - Notifications

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
    static let openMainWindow = Notification.Name("openMainWindow")
}

// MARK: - Window Action Storage

/// Stores the openWindow action so it can be called from MenuBarExtra
final class WindowActionStorage {
    static let shared = WindowActionStorage()
    var openWindow: OpenWindowAction?
}

@main
struct SaneHostsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let updaterController: SPUStandardUpdaterController
    @AppStorage("hideDockIcon") private var hideDockIcon = false
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @StateObject private var menuBarStore = MenuBarProfileStore()

    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        // Faster tooltip appearance (default ~700ms, set to 300ms)
        UserDefaults.standard.set(300, forKey: "NSInitialToolTipDelay")
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(hasSeenWelcome: $hasSeenWelcome)
                .modifier(SettingsLauncher())
                .modifier(WindowActionCapture())
        }
        .defaultSize(width: 900, height: 650)
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Profile") {
                    NotificationCenter.default.post(name: .showNewProfileSheet, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Import Blocklist...") {
                    NotificationCenter.default.post(name: .showImportSheet, object: nil)
                }
                .keyboardShortcut("i", modifiers: .command)
            }

            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }

            CommandGroup(replacing: .help) {
                Button("Show Tutorial") {
                    TutorialState.shared.resetTutorial()
                    hasSeenWelcome = false
                }
            }

            // Keyboard shortcuts
            CommandGroup(after: .sidebar) {
                Divider()
                Button("Deactivate All") {
                    Task { @MainActor in
                        try? await HostsService.shared.deactivateProfile()
                        try? await ProfileStore.shared.deactivate()
                    }
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }
        .onChange(of: hideDockIcon) { _, newValue in
            if newValue {
                NSApp.setActivationPolicy(.accessory)
            } else {
                NSApp.setActivationPolicy(.regular)
                // Bring to front when switching to regular
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        Settings {
            SaneHostsSettingsView(updater: updaterController.updater)
        }

        MenuBarExtra("SaneHosts", systemImage: menuBarStore.activeProfile != nil ? "network.badge.shield.half.filled" : "network") {
            // Status section
            if let active = menuBarStore.activeProfile {
                Text("Active: \(active.name)")
                    .font(.headline)
                Button("Deactivate") {
                    Task { await menuBarStore.deactivateProfile() }
                }
            } else {
                Text("No Active Profile")
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Profiles section
            Section("Profiles") {
                ForEach(menuBarStore.profiles) { profile in
                    Button {
                        Task { await menuBarStore.activateProfile(profile) }
                    } label: {
                        HStack {
                            if menuBarStore.activeProfile?.id == profile.id {
                                Image(systemName: "checkmark")
                            }
                            Text(profile.name)
                        }
                    }
                }
            }

            Divider()

            Button("Open SaneHosts") {
                // Try to find and show existing window first
                if let window = NSApp.windows.first(where: {
                    $0.canBecomeMain &&
                    $0.contentView != nil &&
                    !$0.isMiniaturized &&
                    $0.className.contains("NSWindow")
                }) {
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                } else {
                    // No window exists - use stored openWindow action
                    WindowActionStorage.shared.openWindow?(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            .keyboardShortcut("o")

            SettingsLink {
                Text("Settings...")
            }
            .keyboardShortcut(",")

            Divider()

            Button("Quit SaneHosts") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
    }
}

// MARK: - Settings Launcher Modifier

struct SettingsLauncher: ViewModifier {
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
                try? openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}

// MARK: - Window Action Capture Modifier

struct WindowActionCapture: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .onAppear {
                WindowActionStorage.shared.openWindow = openWindow
            }
    }
}

// MARK: - App Delegate for Dock Menu

class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.mrsane.SaneHosts", category: "AppDelegate")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize activation policy based on preference
        // Since LSUIElement=YES, default is accessory. If hideDockIcon is false, we must force regular.
        if !UserDefaults.standard.bool(forKey: "hideDockIcon") {
            NSApp.setActivationPolicy(.regular)
        }

        // Register the privileged helper daemon for XPC + Touch ID support.
        // This installs the helper as a LaunchDaemon so it can write /etc/hosts as root.
        // First call may prompt the user for authorization (supports Touch ID).
        registerHelperDaemon()
    }

    private func registerHelperDaemon() {
        let daemon = SMAppService.daemon(plistName: HostsHelperConstants.daemonPlistName)

        switch daemon.status {
        case .enabled:
            // Daemon is already registered and launchd starts it on-demand — nothing to do
            logger.info("Helper daemon already enabled")
            return
        case .requiresApproval:
            // User must approve in System Settings > Login Items
            logger.info("Helper daemon requires user approval in System Settings")
            return
        default:
            // .notRegistered, .notFound, or unknown — try to register
            break
        }

        do {
            try daemon.register()
            logger.info("Helper daemon registered successfully")
        } catch {
            // Non-fatal: app falls back to AppleScript for writes
            logger.warning("Failed to register helper daemon: \(error.localizedDescription). Will use AppleScript fallback.")
        }
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let openItem = NSMenuItem(title: "Open SaneHosts", action: #selector(openMainWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        return menu
    }

    @objc func openSettings() {
        // Try notification first (handled by SettingsLauncher in SwiftUI views)
        NotificationCenter.default.post(name: .openSettings, object: nil)
        
        // Fallback: Try standard selector chain
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)

        // Try to find and show existing main window
        if let window = NSApp.windows.first(where: {
            $0.title.contains("SaneHosts") ||
            $0.identifier?.rawValue == "main" ||
            ($0.canBecomeMain && $0.contentView != nil)
        }) {
            window.makeKeyAndOrderFront(nil)
            return
        }

        // No window found - use stored OpenWindowAction from SwiftUI
        WindowActionStorage.shared.openWindow?(id: "main")
    }
}

// MARK: - Menu Bar Profile Store

@MainActor
class MenuBarProfileStore: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var activeProfile: Profile?
    @Published var lastError: String?
    private var notificationObserver: NSObjectProtocol?

    init() {
        Task { await refresh() }
        // Listen for ProfileStore changes instead of polling
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .profileStoreDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncFromSharedStore()
            }
        }
    }

    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func syncFromSharedStore() {
        let shared = ProfileStore.shared
        if profiles != shared.profiles || activeProfile?.id != shared.activeProfile?.id {
            profiles = shared.profiles
            activeProfile = shared.activeProfile
        }
    }

    func refresh() async {
        syncFromSharedStore()
    }

    func activateProfile(_ profile: Profile) async {
        do {
            lastError = nil
            let systemEntries = ProfileStore.shared.systemEntries
            try await HostsService.shared.activateProfile(profile, systemEntries: systemEntries)
            try await ProfileStore.shared.markAsActive(profile: profile)
            syncFromSharedStore()
        } catch {
            lastError = "Failed to activate: \(error.localizedDescription)"
        }
    }

    func deactivateProfile() async {
        do {
            lastError = nil
            try await HostsService.shared.deactivateProfile()
            try await ProfileStore.shared.deactivate()
            syncFromSharedStore()
        } catch {
            lastError = "Failed to deactivate: \(error.localizedDescription)"
        }
    }
}

// MARK: - Menu Item Button Style

struct MenuItemButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered || configuration.isPressed ? Color.accentColor.opacity(0.8) : Color.clear)
            )
            .foregroundStyle(isHovered || configuration.isPressed ? .white : .primary)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

// MARK: - Menu Bar View

struct MenuBarView: View {
    @ObservedObject var store: MenuBarProfileStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Error display
            if let error = store.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                Divider()
            }

            // Active profile status
            if let active = store.activeProfile {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(active.name)
                        .fontWeight(.medium)
                    Spacer()
                    Button("Deactivate") {
                        Task { await store.deactivateProfile() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            } else {
                HStack {
                    Image(systemName: "circle")
                        .foregroundStyle(.secondary)
                    Text("No active profile")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            Divider()
                .padding(.vertical, 4)

            // Profile list
            Text("Profiles")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 2)

            ForEach(store.profiles) { profile in
                Button {
                    Task { await store.activateProfile(profile) }
                } label: {
                    HStack {
                        Image(systemName: store.activeProfile?.id == profile.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(store.activeProfile?.id == profile.id ? .green : .secondary)
                        Text(profile.name)
                        Spacer()
                        Text("\(profile.entries.count)")
                            .font(.caption)
                            .opacity(0.7)
                    }
                }
                .buttonStyle(MenuItemButtonStyle())
            }

            Divider()
                .padding(.vertical, 4)

            Button {
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Text("Open SaneHosts")
            }
            .buttonStyle(MenuItemButtonStyle())

            Button {
                try? openSettings()
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Text("Settings...")
            }
            .buttonStyle(MenuItemButtonStyle())

            Divider()
                .padding(.vertical, 4)

            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit SaneHosts")
            }
            .buttonStyle(MenuItemButtonStyle())
        }
        .padding(.vertical, 6)
        .frame(width: 260)
    }
}

// MARK: - Settings View

struct SaneHostsSettingsView: View {
    @State private var selectedTab = 0
    let updater: SPUUpdater

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab(updater: updater)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(0)

            AboutTab(updater: updater)
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(1)
        }
        .frame(width: 560, height: 500)
    }
}

struct GeneralSettingsTab: View {
    @AppStorage("hideDockIcon") private var hideDockIcon = false
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    let updater: SPUUpdater

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            Logger(subsystem: Bundle.main.bundleIdentifier ?? "SaneHosts", category: "Settings")
                                .error("Failed to \(newValue ? "register" : "unregister") login item: \(error)")
                        }
                    }

                Toggle("Hide Dock icon", isOn: $hideDockIcon)
            } footer: {
                if hideDockIcon {
                    Text("When Dock icon is hidden, access SaneHosts from the menu bar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Software Updates") {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                ))

                Button("Check Now") {
                    updater.checkForUpdates()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AboutTab: View {
    let updater: SPUUpdater
    @State private var showingLicenses = false
    @State private var showingSupport = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // App icon — use runtime icon for proper macOS rendering
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 4)

            VStack(spacing: 8) {
                Text("SaneHosts")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)

                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    Text("Version \(version)")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }

            // Trust info
            HStack(spacing: 0) {
                Text("Made with ❤️ in 🇺🇸")
                    .fontWeight(.medium)
                Text(" · ")
                Text("100% On-Device")
                Text(" · ")
                Text("No Analytics")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.top, 4)

            // Action buttons
            HStack(spacing: 16) {
                Link(destination: URL(string: "https://github.com/sane-apps/SaneHosts")!) {
                    Label("GitHub", systemImage: "link")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    showingLicenses = true
                } label: {
                    Label("Licenses", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    showingSupport = true
                } label: {
                    Label {
                        Text("Support")
                    } icon: {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Link(destination: URL(string: "https://github.com/sane-apps/SaneHosts/issues")!) {
                    Label("Report Issue", systemImage: "ladybug")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.top, 12)

            Button {
                updater.checkForUpdates()
            } label: {
                Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingLicenses) {
            LicensesSheet()
        }
        .sheet(isPresented: $showingSupport) {
            SupportSheet()
        }
    }
}

// MARK: - Licenses Sheet

struct LicensesSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Open Source Licenses")
                .font(.title2)
                .fontWeight(.bold)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LicenseEntry(
                        name: "Sparkle",
                        copyright: "Copyright (c) 2006-2013 Andy Matuschak.\nCopyright (c) 2009-2013 Elgato Systems GmbH.",
                        license: """
                        Permission is hereby granted, free of charge, to any person obtaining a copy of this software \
                        and associated documentation files (the "Software"), to deal in the Software without restriction, \
                        including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, \
                        and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, \
                        subject to the following conditions:

                        The above copyright notice and this permission notice shall be included in all copies or substantial \
                        portions of the Software.

                        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT \
                        LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO \
                        EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER \
                        IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE \
                        USE OR OTHER DEALINGS IN THE SOFTWARE.
                        """
                    )
                }
                .padding()
            }
            .frame(maxHeight: 300)

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.cancelAction)
        }
        .padding()
        .frame(width: 500, height: 420)
    }
}

struct LicenseEntry: View {
    let name: String
    let copyright: String
    let license: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name)
                .font(.headline)
            Text(copyright)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(license)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Support Sheet

struct SupportSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Support SaneHosts")
                .font(.title2)
                .fontWeight(.bold)

            Text("\u{201C}The worker is worthy of his wages.\u{201D}")
                .font(.subheadline)
                .italic()
                .foregroundStyle(.secondary)
            Text("— 1 Timothy 5:18")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Text("SaneHosts is open source and sustained by your support. No VC funding, no ads, no data harvesting — just software that works because someone is paid to maintain it.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("— Mr. Sane")
                .font(.subheadline)
                .fontWeight(.medium)

            Divider()

            Link(destination: URL(string: "https://github.com/sponsors/sane-apps")!) {
                Label("GitHub Sponsors", systemImage: "heart.fill")
            }
            .buttonStyle(.borderedProminent)

            VStack(alignment: .leading, spacing: 8) {
                Text("Or send crypto:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                CryptoAddressRow(label: "BTC", address: "3Go9nJu3dj2qaa4EAYXrTsTf5AnhcrPQke")
                CryptoAddressRow(label: "ETH", address: "0x026668feA51c27F0803055B8c0d881ac2F1e7C3e")
                CryptoAddressRow(label: "SOL", address: "FBvU83GUmwEYk3HMwZh3GBorGvrVVWSPb8VLCKeLiWZZ")
                CryptoAddressRow(label: "ZEC", address: "t1PaQ7LSoRDVvXLaQTWmy5tKUAiKxuE9hBN")
            }

            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
        }
        .padding()
        .frame(width: 480, height: 480)
    }
}

struct CryptoAddressRow: View {
    let label: String
    let address: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .fontWeight(.bold)
                .frame(width: 30, alignment: .leading)

            Text(address)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .textSelection(.enabled)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(address, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Copy \(label) address")
        }
    }
}

// MARK: - Sparkle Check for Updates

struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel

    init(updater: SPUUpdater) {
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates...") {
            checkForUpdatesViewModel.checkForUpdates()
        }
        .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}
