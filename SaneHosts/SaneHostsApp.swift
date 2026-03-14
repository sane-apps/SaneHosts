import os
import SaneHostsFeature
import SaneUI
import ServiceManagement
#if !APP_STORE
    import Sparkle
#endif
import SwiftUI

// MARK: - Notifications

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
    static let openMainWindow = Notification.Name("openMainWindow")
}

// MARK: - Window Action Storage

/// Stores the openWindow action so it can be called from MenuBarExtra
@MainActor
final class WindowActionStorage {
    static let shared = WindowActionStorage()
    var openWindow: OpenWindowAction?

    /// Bring existing main window to front, or create one if none exists
    @MainActor func showMainWindow() {
        // Find an existing main window (SwiftUI WindowGroup id: "main")
        let mainWindow = NSApp.windows.first(where: {
            $0.canBecomeMain &&
                $0.contentView != nil &&
                $0.identifier?.rawValue.contains("main") == true
        })

        if let window = mainWindow {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow?(id: "main")
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

#if !APP_STORE
    @MainActor
    private struct AppleScriptHostsWriteFallback: HostsPrivilegedWriteFallback {
        func writeHostsFile(content: String) async throws {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("sanehosts-pending.hosts")

            try? FileManager.default.removeItem(at: tempURL)

            do {
                try content.write(to: tempURL, atomically: true, encoding: .utf8)
            } catch {
                throw HostsServiceError.tempFileWriteFailed(error.localizedDescription)
            }

            let tempPath = tempURL.path
            guard tempPath.allSatisfy({ $0.isASCII && !$0.isNewline }) else {
                try? FileManager.default.removeItem(at: tempURL)
                throw HostsServiceError.tempFileWriteFailed("Temp path contains unsafe characters")
            }

            let escapedPath = tempPath
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")

            let script = """
            do shell script "cp " & quoted form of "\(escapedPath)" & " /etc/hosts" with administrator privileges
            """

            let result = await runAppleScript(script)
            try? FileManager.default.removeItem(at: tempURL)

            if !result.success {
                throw HostsServiceError.writePermissionDenied(result.error ?? "Unknown error")
            }
        }

        private func runAppleScript(_ script: String) async -> (success: Bool, error: String?) {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    var error: NSDictionary?
                    let appleScript = NSAppleScript(source: script)
                    appleScript?.executeAndReturnError(&error)

                    if let error {
                        let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                        continuation.resume(returning: (false, errorMessage))
                    } else {
                        continuation.resume(returning: (true, nil))
                    }
                }
            }
        }
    }
#endif

@main
struct SaneHostsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #if !APP_STORE
        private let updaterController: SPUStandardUpdaterController
        private let updaterDelegate = SaneHostsUpdaterDelegate()
    #endif
    @AppStorage("hideDockIcon") private var hideDockIcon = !SaneBackgroundAppDefaults.showDockIcon
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @AppStorage("hasSeenWelcomeGate") private var hasSeenWelcomeGate = false
    @StateObject private var menuBarStore = MenuBarProfileStore()
    @State private var licenseService = LicenseService(
        appName: "SaneHosts",
        checkoutURL: LicenseService.directCheckoutURL(appSlug: "sanehosts")
    )

    init() {
        #if !APP_STORE
            updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: updaterDelegate, userDriverDelegate: nil)
            AppDelegate.updater = updaterController.updater
        #endif
        UserDefaults.standard.set(300, forKey: "NSInitialToolTipDelay")
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(licenseService: licenseService)
                .modifier(SettingsLauncher())
                .modifier(WindowActionCapture())
                .preferredColorScheme(.dark)
                .sheet(isPresented: Binding(
                    get: { !hasSeenWelcomeGate },
                    set: {
                        if !$0 {
                            hasSeenWelcomeGate = true
                            hasSeenWelcome = true
                        }
                    }
                )) {
                    WelcomeGateView(
                        appName: "SaneHosts",
                        appIcon: "network.badge.shield.half.filled",
                        freeFeatures: [
                            ("shield.fill", "1 Essentials profile"),
                            ("plus.circle", "Add/edit/delete host entries"),
                            ("arrow.triangle.2.circlepath", "Toggle entries on/off"),
                            ("network", "DNS cache flush")
                        ],
                        proFeatures: [
                            ("checkmark", "Everything in Free, plus:"),
                            ("doc.on.doc", "Unlimited profiles"),
                            ("arrow.down.circle", "Downloadable presets"),
                            ("arrow.triangle.merge", "Merge profiles"),
                            ("checklist", "Bulk enable/disable"),
                            ("square.and.arrow.down", "Import from file/URL"),
                            ("plus.square.on.square", "Duplicate profiles")
                        ],
                        licenseService: licenseService
                    )
                }
                .onAppear {
                    licenseService.checkCachedLicense()
                    let isPro = licenseService.isPro
                    let isFirstLaunch = !hasSeenWelcome
                    if SaneBackgroundAppDefaults.launchAtLogin {
                        _ = SaneLoginItemPolicy.enableByDefaultIfNeeded(isFirstLaunch: isFirstLaunch)
                    }
                    Task.detached {
                        if isPro {
                            await EventTracker.log("app_launch_pro", app: "sanehosts")
                        } else {
                            await EventTracker.log("app_launch_free", app: "sanehosts")
                        }
                        if isFirstLaunch, !isPro {
                            await EventTracker.log("new_free_user", app: "sanehosts")
                        }
                    }
                }
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

            #if !APP_STORE
                CommandGroup(after: .appInfo) {
                    CheckForUpdatesView(updater: updaterController.updater)
                }
            #endif

            CommandGroup(replacing: .help) {
                Button("Show Tutorial") {
                    TutorialState.shared.resetTutorial()
                    TutorialState.shared.startTutorial()
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
            SaneActivationPolicy.applyPolicy(showDockIcon: !newValue)
        }

        Settings {
            #if !APP_STORE
                SaneHostsSettingsView(updater: updaterController.updater, licenseService: licenseService)
                    .preferredColorScheme(.dark)
            #else
                SaneHostsSettingsView(licenseService: licenseService)
                    .preferredColorScheme(.dark)
            #endif
        }

        MenuBarExtra("SaneHosts", systemImage: menuBarStore.activeProfile != nil ? "network.badge.shield.half.filled" : "network") {
            // Status section
            if let active = menuBarStore.activeProfile {
                Button("🟢 Active: \(active.name)") {
                    WindowActionStorage.shared.showMainWindow()
                }
                Button("Deactivate") {
                    Task { await menuBarStore.deactivateProfile() }
                }
            } else {
                Button("🔴 No Active Profile") {
                    WindowActionStorage.shared.showMainWindow()
                }
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
                WindowActionStorage.shared.showMainWindow()
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
    #if !APP_STORE
        weak static var updater: SPUUpdater?
    #endif

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        // Move to /Applications if running from Downloads (Release only)
        #if !DEBUG && !APP_STORE
            SaneAppMover.moveToApplicationsFolderIfNeeded()
        #endif
        #if !APP_STORE
            HostsPrivilegedWriteFallbackRegistry.install(AppleScriptHostsWriteFallback())
        #endif

        let hideDockIcon = UserDefaults.standard.object(forKey: "hideDockIcon") as? Bool ?? !SaneBackgroundAppDefaults.showDockIcon
        SaneActivationPolicy.applyInitialPolicy(showDockIcon: !hideDockIcon)

        // Register the privileged helper daemon for XPC + Touch ID support.
        registerHelperDaemon()
    }

    private func registerHelperDaemon() {
        let daemon = SMAppService.daemon(plistName: HostsHelperConstants.daemonPlistName)
        switch daemon.status {
        case .enabled:
            logger.info("Helper daemon already enabled")
            return
        case .requiresApproval:
            logger.info("Helper daemon requires user approval in System Settings")
            return
        default:
            break
        }
        do {
            try daemon.register()
            logger.info("Helper daemon registered successfully")
        } catch {
            logger.warning("Failed to register helper daemon: \(error.localizedDescription)")
        }
    }

    func applicationDockMenu(_: NSApplication) -> NSMenu? {
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Open SaneHosts", action: #selector(openMainWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        #if !APP_STORE
            let updatesItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
            updatesItem.target = self
            menu.addItem(updatesItem)
        #endif

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

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
        Task { @MainActor in
            WindowActionStorage.shared.showMainWindow()
        }
    }

    #if !APP_STORE
        @objc func checkForUpdates() {
            AppDelegate.updater?.checkForUpdates()
        }
    #endif
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

#if !APP_STORE

    // MARK: - Sparkle Check for Updates

    struct CheckForUpdatesView: View {
        @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel

        init(updater: SPUUpdater) {
            checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
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

    // MARK: - Sparkle Updater Delegate

    final class SaneHostsUpdaterDelegate: NSObject, SPUUpdaterDelegate {
        func feedURLString(for _: SPUUpdater) -> String? {
            "https://sanehosts.com/appcast.xml"
        }
    }
#endif
