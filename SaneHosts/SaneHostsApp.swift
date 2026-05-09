import AppKit
import os
import SaneHostsFeature
import ServiceManagement
#if !APP_STORE
    import Sparkle
#endif
import SwiftUI

// MARK: - Notifications

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
    static let openMainWindow = Notification.Name("openMainWindow")
    static let showSettingsTab = Notification.Name("showSettingsTab")
}

// MARK: - Window Action Storage

/// Stores the openWindow action so it can be called from MenuBarExtra
@MainActor
final class WindowActionStorage {
    static let shared = WindowActionStorage()
    var openWindow: OpenWindowAction?

    /// Bring existing main window to front, or create one if none exists
    @MainActor func showMainWindow(using overrideAction: OpenWindowAction? = nil) {
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
            (overrideAction ?? openWindow)?(id: "main")
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class SettingsActionStorage {
    static let shared = SettingsActionStorage()
    var openSettings: (() -> Void)?

    func capture(_ action: OpenSettingsAction) {
        openSettings = {
            action()
        }
    }

    func showSettings(tab: SaneHostsSettingsTab? = nil) {
        if let openSettings {
            openSettings()
        } else {
            NotificationCenter.default.post(name: .openSettings, object: nil)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }

        if let tab {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .showSettingsTab, object: tab)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

#if !APP_STORE
    @MainActor
    private struct AppleScriptHostsWriteFallback: HostsPrivilegedWriteFallback {
        func writeHostsFile(content: String) async throws {
            do {
                try HostsContentValidator.validate(content)
            } catch {
                throw HostsServiceError.invalidContent
            }

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("sanehosts-\(UUID().uuidString).hosts")

            try? FileManager.default.removeItem(at: tempURL)

            do {
                try content.write(to: tempURL, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tempURL.path)
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
        private let updaterController: SPUStandardUpdaterController?
        private let updaterDelegate = SaneHostsUpdaterDelegate()
        private let updateEligibility: SaneUpdateEligibility
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
            updateEligibility = SaneUpdateEligibility.resolve(
                bundleIdentifier: Bundle.main.bundleIdentifier,
                releaseBundleIdentifier: "com.mrsane.SaneHosts",
                bundlePath: Bundle.main.bundlePath
            )
            if updateEligibility.canUseInAppUpdates {
                updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: updaterDelegate, userDriverDelegate: nil)
                AppDelegate.updater = updaterController?.updater
            } else {
                updaterController = nil
                AppDelegate.updater = nil
            }
            AppDelegate.updateEligibility = updateEligibility
        #endif
        UserDefaults.standard.set(300, forKey: "NSInitialToolTipDelay")
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(licenseService: licenseService)
                .modifier(SettingsLauncher())
                .modifier(SettingsActionCapture())
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
                            ("checkmark", "Everything in Basic, plus:"),
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
                    if isFirstLaunch, SaneBackgroundAppDefaults.launchAtLogin {
                        SaneLoginItemPolicy.scheduleDefaultLaunchAtLoginPrompt(appName: "SaneHosts")
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
            #if !APP_STORE
                SaneHostsAppCommands(updater: updaterController?.updater, updateEligibility: updateEligibility)
            #else
                SaneHostsAppCommands()
            #endif
        }
        .onChange(of: hideDockIcon) { _, newValue in
            SaneActivationPolicy.applyPolicy(showDockIcon: !newValue)
        }

        Settings {
            #if !APP_STORE
                SaneHostsSettingsView(updater: updaterController?.updater, updateEligibility: updateEligibility, licenseService: licenseService)
                    .preferredColorScheme(.dark)
            #else
                SaneHostsSettingsView(licenseService: licenseService)
                    .preferredColorScheme(.dark)
            #endif
        }
        .defaultSize(
            width: 640,
            height: 420
        )
        .windowResizability(.contentSize)

        MenuBarExtra("SaneHosts", systemImage: menuBarStore.activeProfile != nil ? "network.badge.shield.half.filled" : "network") {
            MenuBarMenuContent(store: menuBarStore)
        }
        .menuBarExtraStyle(.menu)
    }
}

struct SaneHostsAppCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    #if !APP_STORE
        let updater: SPUUpdater?
        let updateEligibility: SaneUpdateEligibility
    #endif

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Profile") {
                openMainWindowThen {
                    NotificationCenter.default.post(name: .showNewProfileSheet, object: nil)
                }
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Import Blocklist...") {
                openMainWindowThen {
                    NotificationCenter.default.post(name: .showImportSheet, object: nil)
                }
            }
            .keyboardShortcut("i", modifiers: .command)
        }

        #if !APP_STORE
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updater, updateEligibility: updateEligibility)
            }
        #endif

        CommandGroup(replacing: .help) {
            Button("Show Tutorial") {
                openMainWindowThen {
                    TutorialState.shared.resetTutorial()
                    TutorialState.shared.startTutorial()
                }
            }
        }

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

    private func openMainWindowThen(_ action: @escaping @MainActor () -> Void) {
        WindowActionStorage.shared.showMainWindow(using: openWindow)
        DispatchQueue.main.async {
            action()
        }
    }
}

// MARK: - Settings Launcher Modifier

struct SettingsLauncher: ViewModifier {
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}

struct SettingsActionCapture: ViewModifier {
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content
            .onAppear {
                SettingsActionStorage.shared.capture(openSettings)
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
        static var updateEligibility: SaneUpdateEligibility = .notInstalledInApplications
    #endif

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        // Move to /Applications if running from Downloads (Release only)
        #if !DEBUG && !APP_STORE
            SaneAppMover.moveToApplicationsFolderIfNeeded(prompt: .init(
                messageText: "Move to Applications?",
                informativeText: "{appName} works best from your Applications folder. Move it there now? You may be asked for your password.",
                moveButtonTitle: "Move to Applications",
                cancelButtonTitle: "Not Now"
            ))
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

        menu.addItem(SaneStandardMenu.openAppItem(
            appName: "SaneHosts",
            target: self,
            action: #selector(openMainWindow)
        ))

        menu.addItem(NSMenuItem.separator())

        SaneStandardMenu.addCoreUtilityItems(
            to: menu,
            appName: "SaneHosts",
            target: self,
            settingsAction: #selector(openSettings),
            licenseAction: #selector(openLicense),
            checkForUpdatesAction: directUpdateAction,
            configureCheckForUpdates: directUpdateConfigurator,
            aboutAndBugReportAction: #selector(openAbout),
            quitAction: #selector(quit),
            settingsKeyEquivalent: ""
        )

        return menu
    }

    @MainActor @objc func openSettings() {
        SettingsActionStorage.shared.showSettings()
    }

    @MainActor @objc func openLicense() {
        SettingsActionStorage.shared.showSettings(tab: .license)
    }

    @MainActor @objc func openAbout() {
        SettingsActionStorage.shared.showSettings(tab: .about)
    }

    @objc func openMainWindow() {
        Task { @MainActor in
            WindowActionStorage.shared.showMainWindow()
        }
    }

    #if !APP_STORE
        private var directUpdateAction: Selector? {
            #selector(checkForUpdates)
        }

        private var directUpdateConfigurator: ((NSMenuItem) -> Void)? {
            { [weak self] item in
                self?.configureUpdateItem(item)
            }
        }

        private func configureUpdateItem(_ item: NSMenuItem) {
            let canUpdate = Self.updateEligibility.canUseInAppUpdates && Self.updater != nil
            item.isEnabled = canUpdate
            item.toolTip = canUpdate ? nil : Self.updateEligibility.userFacingStatus
        }

        @objc func checkForUpdates() {
            guard Self.updateEligibility.canUseInAppUpdates, let updater = AppDelegate.updater else {
                NSSound.beep()
                return
            }
            updater.checkForUpdates()
        }
    #else
        private var directUpdateAction: Selector? { nil }
        private var directUpdateConfigurator: ((NSMenuItem) -> Void)? { nil }
    #endif

    @objc func quit() {
        NSApp.terminate(nil)
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
        lastError = shared.error?.localizedDescription
    }

    func refresh() async {
        let shared = ProfileStore.shared
        if ProfileStoreBootstrapPolicy.shouldLoad(
            profileCount: shared.profiles.count,
            isLoading: shared.isLoading
        ) {
            await shared.load()
        }
        syncFromSharedStore()
    }

    func activateProfile(_ profile: Profile) async {
        do {
            lastError = nil
            let systemEntries = ProfileStore.shared.systemEntries
            try await HostsService.shared.activateProfile(profile, systemEntries: systemEntries)
            try await ProfileStore.shared.markAsActive(profile: profile)
            syncFromSharedStore()
            if markFirstValueActionIfNeeded() {
                await EventTracker.log("first_value_action", app: "sanehosts")
            }
        } catch {
            lastError = "Failed to activate: \(error.localizedDescription)"
        }
    }

    private func markFirstValueActionIfNeeded() -> Bool {
        let key = "SaneApps.EventTracker.logged.sanehosts.first_value_action"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        UserDefaults.standard.set(true, forKey: key)
        return true
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

struct MenuBarMenuContent: View {
    @ObservedObject var store: MenuBarProfileStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            if let active = store.activeProfile {
                Button("🟢 Active: \(active.name)") {
                    WindowActionStorage.shared.showMainWindow(using: openWindow)
                }
                Button("Deactivate") {
                    Task { await store.deactivateProfile() }
                }
            } else {
                Button("🔴 No Active Profile") {
                    WindowActionStorage.shared.showMainWindow(using: openWindow)
                }
            }

            Divider()

            Section("Profiles") {
                ForEach(store.profiles) { profile in
                    Button {
                        Task { await store.activateProfile(profile) }
                    } label: {
                        HStack {
                            if store.activeProfile?.id == profile.id {
                                Image(systemName: "checkmark")
                            }
                            Text(profile.name)
                        }
                    }
                }
            }

            Divider()

            Button("Open SaneHosts") {
                WindowActionStorage.shared.showMainWindow(using: openWindow)
            }
            .keyboardShortcut("o")

            Button(SaneStandardMenu.settingsTitle) {
                SettingsActionStorage.shared.showSettings()
            }
            .keyboardShortcut(",")

            Button(SaneStandardMenu.licenseTitle) {
                SettingsActionStorage.shared.showSettings(tab: .license)
            }

            Button(SaneStandardMenu.aboutAndBugReportTitle) {
                SettingsActionStorage.shared.showSettings(tab: .about)
            }

            #if !APP_STORE
            Button(SaneStandardMenu.checkForUpdatesTitle) {
                guard AppDelegate.updateEligibility.canUseInAppUpdates, let updater = AppDelegate.updater else {
                    NSSound.beep()
                    return
                }
                updater.checkForUpdates()
            }
            .disabled(!AppDelegate.updateEligibility.canUseInAppUpdates || AppDelegate.updater == nil)
            #endif

            Divider()

            Button("Quit SaneHosts") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .onAppear {
            WindowActionStorage.shared.openWindow = openWindow
            SettingsActionStorage.shared.capture(openSettings)
        }
    }
}

#if !APP_STORE

    // MARK: - Sparkle Check for Updates

    struct CheckForUpdatesView: View {
        @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel

        init(updater: SPUUpdater?, updateEligibility: SaneUpdateEligibility) {
            checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater, updateEligibility: updateEligibility)
        }

        var body: some View {
            Button(SaneStandardMenu.checkForUpdatesTitle) {
                checkForUpdatesViewModel.checkForUpdates()
            }
            .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
            .help(checkForUpdatesViewModel.statusText)
        }
    }

    final class CheckForUpdatesViewModel: ObservableObject {
        @Published var canCheckForUpdates = false
        @Published var statusText: String = ""
        private let updater: SPUUpdater?
        private let updateEligibility: SaneUpdateEligibility

        init(updater: SPUUpdater?, updateEligibility: SaneUpdateEligibility) {
            self.updater = updater
            self.updateEligibility = updateEligibility
            statusText = updateEligibility.canUseInAppUpdates ? "" : updateEligibility.userFacingStatus
            guard updateEligibility.canUseInAppUpdates, let updater else { return }
            updater.publisher(for: \.canCheckForUpdates)
                .assign(to: &$canCheckForUpdates)
        }

        func checkForUpdates() {
            guard updateEligibility.canUseInAppUpdates, let updater else {
                NSSound.beep()
                return
            }
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
