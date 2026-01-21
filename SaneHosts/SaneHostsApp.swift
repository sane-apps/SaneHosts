import SwiftUI
import SaneHostsFeature
import ServiceManagement
import Sparkle

// MARK: - Notifications

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
}

@main
struct SaneHostsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let updaterController: SPUStandardUpdaterController
    @AppStorage("showInMenuBar") private var showInMenuBar = true
    @AppStorage("hideDockIcon") private var hideDockIcon = false
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @StateObject private var menuBarStore = MenuBarProfileStore()

    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(hasSeenWelcome: $hasSeenWelcome)
                .modifier(SettingsLauncher())
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
            SaneHostsSettingsView()
        }

        MenuBarExtra("SaneHosts", systemImage: menuBarStore.activeProfile != nil ? "network.badge.shield.half.filled" : "network", isInserted: $showInMenuBar) {
            MenuBarView(store: menuBarStore)
                .modifier(SettingsLauncher())
        }
        .menuBarExtraStyle(.window)
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

// MARK: - App Delegate for Dock Menu

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize activation policy based on preference
        // Since LSUIElement=YES, default is accessory. If hideDockIcon is false, we must force regular.
        if !UserDefaults.standard.bool(forKey: "hideDockIcon") {
            NSApp.setActivationPolicy(.regular)
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
        if let window = NSApp.windows.first(where: { $0.title == "SaneHosts" || $0.identifier?.rawValue == "main" }) {
            window.makeKeyAndOrderFront(nil)
        }
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

// MARK: - Menu Bar View

struct MenuBarView: View {
    @ObservedObject var store: MenuBarProfileStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Error display
            if let error = store.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(.horizontal)
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
                .padding(.horizontal)
            } else {
                HStack {
                    Image(systemName: "circle")
                        .foregroundStyle(.secondary)
                    Text("No active profile")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }

            Divider()

            // Profile list
            Text("Profiles")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

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
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.vertical, 4)
            }

            Divider()

            Button("Open SaneHosts") {
                NSApp.activate(ignoringOtherApps: true)
            }
            .padding(.horizontal)

            Button("Settings...") {
                try? openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
            .padding(.horizontal)

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .frame(width: 280)
    }
}

// MARK: - Settings View

struct SaneHostsSettingsView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(0)

            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(1)
        }
        .frame(width: 450, height: 300)
    }
}

struct GeneralSettingsTab: View {
    @AppStorage("showInMenuBar") private var showInMenuBar = true
    @AppStorage("hideDockIcon") private var hideDockIcon = false
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        Form {
            Section {
                Toggle("Show in menu bar", isOn: $showInMenuBar)
                    .onChange(of: showInMenuBar) { _, newValue in
                        // Prevent hiding both
                        if !newValue && hideDockIcon {
                            hideDockIcon = false
                        }
                    }
                
                Toggle("Hide Dock icon", isOn: $hideDockIcon)
                    .onChange(of: hideDockIcon) { _, newValue in
                        // Prevent hiding both
                        if newValue {
                            showInMenuBar = true
                        }
                    }
                
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            print("Failed to \(newValue ? "register" : "unregister") login item: \(error)")
                        }
                    }
            } footer: {
                if hideDockIcon {
                    Text("When Dock icon is hidden, access SaneHosts from the menu bar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "network.badge.shield.half.filled")
                .font(.system(size: 64))
                .foregroundStyle(.indigo)

            Text("SaneHosts")
                .font(.title)
                .fontWeight(.bold)

            Text("Version 1.0")
                .foregroundStyle(.secondary)

            Divider()

            VStack(spacing: 8) {
                Link(destination: URL(string: "https://sanehosts.com")!) {
                    Label("Website", systemImage: "globe")
                }

                Link(destination: URL(string: "https://github.com/sane-apps/SaneHosts")!) {
                    Label("GitHub", systemImage: "link")
                }

                Link(destination: URL(string: "https://github.com/sane-apps/SaneHosts/issues")!) {
                    Label("Report Issue", systemImage: "ladybug")
                }
            }

            Spacer()

            Text("Made with care by Mr. Sane")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
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
