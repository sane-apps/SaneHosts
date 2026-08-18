import AppKit
import Foundation
@testable import SaneHostsFeature
import Testing

@Suite("MainView Gate Policy Tests")
struct MainViewGatePolicyTests {
    @Test("Default SaneHosts license service enables a 14 day trial")
    func defaultLicenseServiceEnablesFourteenDayProTrial() throws {
        let testURL = URL(fileURLWithPath: #filePath)
        let appRoot = testURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = try String(contentsOf: appRoot.appendingPathComponent("SaneHosts/SaneHostsApp.swift"))
        let contentSource = try String(contentsOf: appRoot.appendingPathComponent("SaneHostsPackage/Sources/SaneHostsFeature/ContentView.swift"))
        let mainSource = try String(contentsOf: appRoot.appendingPathComponent("SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView.swift"))

        for source in [appSource, contentSource, mainSource] {
            #expect(source.contains("proTrial: .init(storageKeyPrefix: \"sanehosts.pro_trial\")"))
        }
    }

    @Test("Unlicensed users cannot open remote import from empty state")
    func basicCannotOpenRemoteImport() {
        #expect(MainViewGatePolicy.canOpenRemoteImport(isPro: false) == false)
    }

    @Test("Paid users can open remote import from empty state")
    func proCanOpenRemoteImport() {
        #expect(MainViewGatePolicy.canOpenRemoteImport(isPro: true))
    }

    @Test("Expired trial does not fall back to unpaid use")
    func expiredTrialDoesNotFallBackToUnpaidUse() {
        #expect(MainViewGatePolicy.allowsUseAfterTrial(hasExpiredProTrial: true) == false)
        #expect(MainViewGatePolicy.allowsUseAfterTrial(hasExpiredProTrial: false) == false)
    }

    @Test("Expired trial menu routes profile activation to main window gate")
    func expiredTrialMenuRoutesProfileActivationToMainWindowGate() throws {
        let testURL = URL(fileURLWithPath: #filePath)
        let appRoot = testURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = try String(contentsOf: appRoot.appendingPathComponent("SaneHosts/SaneHostsApp.swift"))

        #expect(appSource.contains("Task { await store.activateProfile(profile) }"))
        #expect(appSource.contains("if licenseService.hasExpiredProTrial {\n                            WindowActionStorage.shared.showMainWindow(using: openWindow)\n                        } else {\n                            Task { await store.activateProfile(profile) }\n                        }"))
    }

    @Test("Trial countdown copy is short and tactful")
    func trialCountdownCopy() {
        #expect(MainViewGatePolicy.trialCountdownTitle(daysRemaining: 14) == "14 days left in trial")
        #expect(MainViewGatePolicy.trialCountdownTitle(daysRemaining: 1) == "1 day left in trial")
        #expect(MainViewGatePolicy.trialCountdownTitle(daysRemaining: nil) == nil)
    }

    @Test("Protection copy matches the actual hosts write and authentication behavior")
    func protectionCopyIsTruthful() {
        #expect(ProtectionUXCopy.turnOffActionTitle == "Turn Off Protection…")
        #expect(ProtectionUXCopy.activePersistence == "Protection stays active when SaneHosts is closed or quit.")
        #expect(ProtectionUXCopy.authenticationRequirement == "Allow SaneHosts in Login Items once. After that, switching profiles does not ask for your password each time.")
        #expect(ProtectionUXCopy.deactivationImpact == "Turning it off removes this profile’s rules while leaving standard hosts entries.")
        #expect(!ProtectionUXCopy.deactivationImpact.localizedCaseInsensitiveContains("original hosts file"))
    }

    @Test("Normal workspace restores the main window close control")
    @MainActor
    func normalWorkspaceRestoresMainWindowCloseControl() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.styleMask.remove(.closable)

        SaneHostsWindowPolicy.restoreCloseControl(for: window)

        #expect(window.styleMask.contains(.closable))
        #expect(window.standardWindowButton(.closeButton)?.isEnabled == true)
    }

    @Test("Customer UI fixture is process-only and does not rewrite user preferences")
    func customerUIFixtureIsProcessOnly() throws {
        let testURL = URL(fileURLWithPath: #filePath)
        let appRoot = testURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = try String(contentsOf: appRoot.appendingPathComponent("SaneHosts/SaneHostsApp.swift"))
        let executorSource = try String(contentsOf: appRoot.appendingPathComponent("scripts/customer_ui_action_executor.rb"))

        #expect(appSource.contains("static let customerUIFixtureKey = \"SANEHOSTS_CUSTOMER_UI_FIXTURE\""))
        #expect(appSource.contains("@State private var customerUIWelcomeGatePresented"))
        #expect(appSource.contains("autoDismissOnPro: false"))
        #expect(appSource.contains(".sheet(isPresented: welcomeGatePresentation)"))
        #expect(appSource.contains("isCustomerUIFixture ? true : !hideDockIcon"))
        #expect(!executorSource.contains("system!('/usr/bin/defaults', 'write'"))
    }

    @Test("Active profile detail and quick action render the truthful protection copy")
    func activeProtectionCopyIsWiredIntoUI() throws {
        let testURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let detailSource = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/SaneHostsFeature/Views/ProfileDetailView.swift")
        )
        let layoutSource = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/SaneHostsFeature/Views/MainView+Layout.swift")
        )

        #expect(detailSource.contains("Text(ProtectionUXCopy.activePersistence)"))
        #expect(detailSource.contains("Text(ProtectionUXCopy.authenticationRequirement)"))
        #expect(detailSource.contains("Text(ProtectionUXCopy.deactivationImpact)"))
        #expect(detailSource.contains(".foregroundColor(.white)"))
        #expect(layoutSource.contains("primaryProfile.isActive ? ProtectionUXCopy.turnOffActionTitle"))
        #expect(layoutSource.contains("primaryProfile.isActive ? ProtectionUXCopy.quickDeactivationImpact"))
        #expect(!layoutSource.localizedCaseInsensitiveContains("original hosts file"))
    }

    @Test("Protection-level rows expose their tap behavior to accessibility")
    func protectionLevelRowsExposeAccessibilityAction() throws {
        let testURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let layoutSource = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/SaneHostsFeature/Views/MainView+Layout.swift")
        )

        #expect(layoutSource.contains(".accessibilityLabel(\"\\(preset.displayName) protection level\")"))
        #expect(layoutSource.contains(".accessibilityLabel(\"\\(profile.name), \\(profile.isActive ? \"active\" : \"inactive\"), \\(profile.entryCount) entries\")"))
        #expect(layoutSource.components(separatedBy: ".accessibilityAddTraits(.isButton)").count - 1 >= 2)
        #expect(layoutSource.contains(".accessibilityAction {"))
        #expect(layoutSource.contains("selectedProfileIDs = [profile.id]"))
        #expect(layoutSource.components(separatedBy: "selectedPreset = preset").count - 1 == 2)
        #expect(layoutSource.components(separatedBy: "showPresetUpsell(for: preset)").count - 1 == 3)
    }

    @Test("User-cancelled authentication is quiet while real failures stay contextual")
    func userCancellationIsQuiet() {
        let cancelledMessage = HostsServiceError.actionErrorMessage(
            for: HostsServiceError.userCancelled,
            action: "Couldn’t activate Family Safe"
        )
        let realFailureMessage = HostsServiceError.actionErrorMessage(
            for: HostsServiceError.helperUnavailable,
            action: "Couldn’t activate Family Safe"
        )

        #expect(cancelledMessage == nil)
        #expect(realFailureMessage?.hasPrefix("Couldn’t activate Family Safe: ") == true)
        #expect(realFailureMessage?.contains("helper service") == true)
    }

    @Test("Main-window and menu-bar actions use quiet cancellation mapping")
    func activationSurfacesUseQuietCancellationMapping() throws {
        let testURL = URL(fileURLWithPath: #filePath)
        let appRoot = testURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let actionsSource = try String(
            contentsOf: appRoot.appendingPathComponent("SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView+Actions.swift")
        )
        let appSource = try String(contentsOf: appRoot.appendingPathComponent("SaneHosts/SaneHostsApp.swift"))

        let mainWindowMappings = actionsSource.components(separatedBy: "HostsServiceError.actionErrorMessage(").count - 1
        let appAndMenuMappings = appSource.components(separatedBy: "HostsServiceError.actionErrorMessage(").count - 1
        #expect(mainWindowMappings == 2)
        #expect(appAndMenuMappings == 3)
        #expect(!actionsSource.contains("activationError = error.localizedDescription"))
        #expect(!appSource.contains("lastError = \"Failed to activate:"))
    }

    @Test("Single-profile context deletion uses the existing confirmation route")
    func singleProfileDeletionUsesConfirmation() throws {
        let testURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let actionsSource = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/SaneHostsFeature/Views/MainView+Actions.swift")
        )

        #expect(actionsSource.contains("selectedProfileIDs = [profile.id]\n                deleteWithConfirmation()"))
        #expect(!actionsSource.contains("deleteProfile(profile)"))
    }

    @Test("Essentials is the default when no prior selection exists")
    func essentialsIsDefaultSelection() {
        let essentials = Profile(id: UUID(), name: "Essentials")
        let strict = Profile(id: UUID(), name: "Strict")

        let selection = MainViewSelectionPolicy.initialSelection(
            profiles: [strict, essentials],
            isPro: false,
            currentSelection: []
        )

        #expect(selection == [essentials.id])
    }

    @Test("Existing valid selection is preserved on reload")
    func existingSelectionIsPreserved() {
        let essentials = Profile(id: UUID(), name: "Essentials")
        let strict = Profile(id: UUID(), name: "Strict")

        let selection = MainViewSelectionPolicy.initialSelection(
            profiles: [essentials, strict],
            isPro: false,
            currentSelection: [strict.id]
        )

        #expect(selection == [strict.id])
    }

    @Test("Falls back to active profile when Essentials missing")
    func fallsBackToActiveProfile() {
        let active = Profile(id: UUID(), name: "Custom", isActive: true)
        let other = Profile(id: UUID(), name: "Another")

        let selection = MainViewSelectionPolicy.initialSelection(
            profiles: [other, active],
            isPro: false,
            currentSelection: []
        )

        #expect(selection == [active.id])
    }
}

@Suite("Profile Store Bootstrap Policy Tests")
struct ProfileStoreBootstrapPolicyTests {
    @Test("Menu bar bootstrap loads when the shared store is still empty")
    func loadsWhenStoreIsEmpty() {
        #expect(ProfileStoreBootstrapPolicy.shouldLoad(profileCount: 0, isLoading: false))
    }

    @Test("Menu bar bootstrap does not double-load while a load is already running")
    func skipsWhileLoadIsRunning() {
        #expect(ProfileStoreBootstrapPolicy.shouldLoad(profileCount: 0, isLoading: true) == false)
    }

    @Test("Menu bar bootstrap does not reload once profiles are already available")
    func skipsWhenProfilesAlreadyLoaded() {
        #expect(ProfileStoreBootstrapPolicy.shouldLoad(profileCount: 1, isLoading: false) == false)
    }
}

@Suite("Profile Store Essentials Policy Tests")
struct ProfileStoreEssentialsPolicyTests {
    @Test("Creates Essentials when migration already created Existing Entries")
    func createsEssentialsAlongsideExistingEntries() {
        let existingEntries = Profile(name: "Existing Entries", source: .system)

        #expect(ProfileStoreEssentialsPolicy.needsEssentialsProfile(profiles: [existingEntries]))
    }

    @Test("Does not duplicate Essentials when it already exists")
    func doesNotDuplicateExistingEssentials() {
        let essentials = Profile(name: "Essentials")
        let existingEntries = Profile(name: "Existing Entries", source: .system)

        #expect(ProfileStoreEssentialsPolicy.needsEssentialsProfile(profiles: [existingEntries, essentials]) == false)
    }

    @Test("Essentials matching is case insensitive")
    func essentialsMatchingIsCaseInsensitive() {
        let essentials = Profile(name: "essentials")

        #expect(ProfileStoreEssentialsPolicy.needsEssentialsProfile(profiles: [essentials]) == false)
    }

    @Test("Empty Essentials stub is detected for refill")
    func emptyEssentialsStubNeedsRefill() {
        let empty = Profile(name: "Essentials")
        let populated = Profile(
            name: "Essentials",
            entries: [HostEntry(ipAddress: "0.0.0.0", hostnames: ["ads.example"])]
        )

        #expect(ProfileStoreEssentialsPolicy.emptyEssentialsProfile(in: [empty])?.id == empty.id)
        #expect(ProfileStoreEssentialsPolicy.emptyEssentialsProfile(in: [populated]) == nil)
    }
}

@Suite("Hosts Write Auth Policy Tests")
struct HostsWriteAuthPolicyTests {
    @Test("Running helper does not ask for a password on every write")
    func helperWriteDoesNotPromptAgain() {
        #expect(HostsWriteAuthPolicy.requiresLocalAuthentication(helperRunning: true) == false)
        #expect(HostsWriteAuthPolicy.requiresLocalAuthentication(helperRunning: false) == true)
    }
}

@Suite("Entry Row Layout Policy Tests")
struct EntryRowLayoutPolicyTests {
    @Test("IPv4 addresses stay on one line in the entry table")
    func ipAddressesStayOnOneLine() throws {
        let testURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let designSource = try String(contentsOf: packageRoot.appendingPathComponent("Sources/SaneHostsFeature/DesignSystem/DesignSystem.swift"))
        let detailSource = try String(contentsOf: packageRoot.appendingPathComponent("Sources/SaneHostsFeature/Views/ProfileDetailComponents.swift"))

        #expect(designSource.contains(".lineLimit(1)"))
        #expect(designSource.contains(".fixedSize(horizontal: true, vertical: false)"))
        #expect(detailSource.contains(".frame(width: 140, alignment: .leading)"))
    }
}

@Suite("Dark Mode Readability Policy Tests")
struct DarkModeReadabilityPolicyTests {
    @Test("Customer-facing dark UI does not use secondary gray semantics")
    func customerFacingDarkUIDoesNotUseSecondaryGraySemantics() throws {
        let testURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let files = [
            "Sources/SaneHostsFeature/DesignSystem/DesignSystem.swift",
            "Sources/SaneHostsFeature/Views/MainView.swift",
            "Sources/SaneHostsFeature/Views/MainView+Actions.swift",
            "Sources/SaneHostsFeature/Views/MainView+Layout.swift",
            "Sources/SaneHostsFeature/Views/MainViewComponents.swift",
            "Sources/SaneHostsFeature/Views/ProfileCreationSheets.swift",
            "Sources/SaneHostsFeature/Views/PresetViews.swift",
            "Sources/SaneHostsFeature/Views/FetchProgressOverlay.swift",
            "Sources/SaneHostsFeature/Views/MergeProfilesSheet.swift",
            "Sources/SaneHostsFeature/Views/RemoteImportSheet.swift",
            "Sources/SaneHostsFeature/Views/RemoteImportSheet+Catalog.swift",
            "Sources/SaneHostsFeature/Views/RemoteImportSheet+Import.swift",
            "Sources/SaneHostsFeature/Views/ProfileDetailView.swift"
        ]

        let combinedSource = try files.map {
            try String(contentsOf: packageRoot.appendingPathComponent($0))
        }.joined(separator: "\n")

        #expect(!combinedSource.contains("Color.secondary"))
        #expect(!combinedSource.contains("color: .secondary"))
        #expect(!combinedSource.contains("iconColor: .secondary"))
        #expect(!combinedSource.contains("foregroundStyle(.secondary"))
    }

    @Test("Sidebar profile names explicitly stay white")
    func sidebarProfileNamesExplicitlyStayWhite() throws {
        let testURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let mainSource = try String(contentsOf: packageRoot.appendingPathComponent("Sources/SaneHostsFeature/Views/MainViewComponents.swift"))

        #expect(mainSource.contains("Text(profile.name)"))
        #expect(mainSource.contains(".foregroundColor(.white)"))
    }

    @Test("Tutorial overlay remains visibly explainable instead of blacking out the app")
    func tutorialOverlayRemainsVisiblyExplainable() throws {
        let testURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let overlaySource = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/SaneHostsFeature/Views/CoachMarkOverlay.swift")
        )

        #expect(overlaySource.contains("CGRect(origin: .zero, size: proxy.size)"))
        #expect(overlaySource.contains(".black.opacity(0.45)"))
        #expect(overlaySource.contains(".fill(Color.black.opacity(0.92))"))
        #expect(overlaySource.contains(".foregroundColor(.white)"))
    }
}

@Suite("Runtime Resource Policy Tests")
struct RuntimeResourcePolicyTests {
    @Test("Remote import cancellation cancels service and detached parse work")
    func remoteImportCancellationCancelsServiceAndParseWork() throws {
        let testURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let syncSource = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/SaneHostsFeature/Services/RemoteSyncService.swift")
        )

        #expect(syncSource.contains("private var currentTask: Task<RemoteHostsFile, Error>?"))
        #expect(syncSource.contains("currentTask = task"))
        #expect(syncSource.contains("currentTask?.cancel()"))
        #expect(syncSource.contains("withTaskCancellationHandler"))
        #expect(syncSource.contains("parseTask.cancel()"))
    }

    @Test("Remote import URL checks are bounded and cancelled with the sheet")
    func remoteImportURLChecksAreBoundedAndCancelledWithSheet() throws {
        let testURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let files = [
            "Sources/SaneHostsFeature/Views/RemoteImportSheet.swift",
            "Sources/SaneHostsFeature/Views/RemoteImportSheet+Catalog.swift"
        ]
        let mainSource = try files.map {
            try String(contentsOf: packageRoot.appendingPathComponent($0))
        }.joined(separator: "\n")

        #expect(mainSource.contains("@State var urlCheckTask: Task<Void, Never>?"))
        #expect(mainSource.contains("let concurrencyLimit = 6"))
        #expect(mainSource.contains("urlCheckTask?.cancel()"))
        #expect(mainSource.contains("group.cancelAll()"))
        #expect(mainSource.contains(".onDisappear"))
    }

    @Test("Large entry filtering is evaluated once per entries render pass")
    func largeEntryFilteringIsEvaluatedOncePerEntriesRenderPass() throws {
        let testURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let detailSource = try String(contentsOf: packageRoot.appendingPathComponent("Sources/SaneHostsFeature/Views/ProfileDetailView.swift"))

        #expect(detailSource.contains("let matchingEntries = filteredEntries"))
        #expect(detailSource.contains("let matchingCount = matchingEntries.count"))
        #expect(detailSource.contains("Array(matchingEntries.prefix(Self.maxVisibleEntries))"))
        #expect(detailSource.contains("Showing \\(compactNumber(profile.entries.count)) of \\(compactNumber(profile.entryCount)) entries"))
    }

    @Test("Activation and deactivation paths reject concurrent writes")
    func activationAndDeactivationPathsRejectConcurrentWrites() throws {
        let testURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let mainSource = try String(contentsOf: packageRoot.appendingPathComponent("Sources/SaneHostsFeature/Views/MainView+Actions.swift"))

        #expect(mainSource.contains("guard !isActivating else { return }"))
        #expect(mainSource.contains("defer { isActivating = false }"))
        #expect(mainSource.contains("try? await store.deactivate()"))
    }

    @Test("Large profile summaries keep full entry counts without eagerly loading every entry")
    func largeProfileSummariesKeepFullEntryCounts() {
        let preview = HostEntry(ipAddress: "0.0.0.0", hostnames: ["ads.example.com"])
        let profile = Profile(
            name: "Large",
            entries: [preview],
            entryCountOverride: 100_000,
            enabledCountOverride: 90000,
            disabledCountOverride: 10000
        )

        #expect(profile.entryCount == 100_000)
        #expect(profile.hasPartialEntries)
        #expect(profile.entryCounts.enabled == 90000)
        #expect(profile.entryCounts.disabled == 10000)
    }

    @Test("Large profile operations load full profile content before destructive or exported writes")
    func largeProfileOperationsLoadFullProfileContentBeforeWrites() throws {
        let testURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let mainSource = try String(contentsOf: packageRoot.appendingPathComponent("Sources/SaneHostsFeature/Views/MainView+Actions.swift"))
        let storeSource = try String(contentsOf: packageRoot.appendingPathComponent("Sources/SaneHostsFeature/Services/ProfileStore.swift"))

        #expect(mainSource.contains("let fullProfile = try await store.fullProfile(for: profile)"))
        #expect(mainSource.contains("HostsService.shared.activateProfile(fullProfile"))
        #expect(mainSource.contains("let fullProfile = try await store.fullProfile(for: profile)\n                    let content = store.exportProfile(fullProfile)"))
        #expect(storeSource.contains("let sourceProfile = try await fullProfile(for: profile)"))
        #expect(storeSource.contains("let fullProfile = try await fullProfile(for: profile)"))
    }

    @Test("Large profile loading uses summaries at startup and bounded accumulation during import")
    func largeProfileLoadingUsesSummariesAndImportBounds() throws {
        let testURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let importSource = try String(contentsOf: packageRoot.appendingPathComponent("Sources/SaneHostsFeature/Views/RemoteImportSheet+Import.swift"))
        let storeSource = try String(contentsOf: packageRoot.appendingPathComponent("Sources/SaneHostsFeature/Services/ProfileStore.swift"))
        let directoryLoaderSource = try String(contentsOf: packageRoot.appendingPathComponent("Sources/SaneHostsFeature/Services/ProfileDirectoryLoader.swift"))
        let summaryLoaderSource = try String(contentsOf: packageRoot.appendingPathComponent("Sources/SaneHostsFeature/Services/LargeProfileSummaryLoader.swift"))

        #expect(directoryLoaderSource.contains("largeProfileSummaryThresholdBytes"))
        #expect(directoryLoaderSource.contains("LargeProfileSummaryLoader.loadSummary"))
        #expect(directoryLoaderSource.contains("largeProfilePreviewEntryLimit"))
        #expect(summaryLoaderSource.contains("Data(contentsOf: url, options: [.mappedIfSafe])"))
        #expect(!storeSource.contains("String(decoding: data"))
        #expect(!summaryLoaderSource.contains("String(decoding: data"))
        #expect(importSource.contains("let maxImportedEntries = 500_000"))
        #expect(importSource.contains("try Task.checkCancellation()"))
        #expect(importSource.contains("guard allEntries.count < maxImportedEntries else { break }"))
    }

    @Test("Privileged fallback refreshes DNS inside its authorized write")
    func privilegedFallbackRefreshesDNSInsideAuthorizedWrite() throws {
        let testURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let repoRoot = packageRoot.deletingLastPathComponent()
        let appSource = try String(contentsOf: repoRoot.appendingPathComponent("SaneHosts/SaneHostsApp.swift"))
        let dnsSource = try String(contentsOf: packageRoot.appendingPathComponent("Sources/SaneHostsFeature/Services/DNSService.swift"))
        let hostsSource = try String(contentsOf: packageRoot.appendingPathComponent("Sources/SaneHostsFeature/Services/HostsService.swift"))
        let helperSource = try String(contentsOf: repoRoot.appendingPathComponent("SaneHostsHelper/main.swift"))

        #expect(appSource.contains("let warning = try await HostsService.shared.deactivateProfile()"))
        #expect(!appSource.contains("try? await HostsService.shared.deactivateProfile()"))
        #expect(appSource.contains("/usr/bin/dscacheutil -flushcache && /usr/bin/killall -HUP mDNSResponder"))
        #expect(appSource.contains("with administrator privileges"))
        #expect(appSource.contains("HostsPrivilegedWriteResult(didRefreshDNSCache:"))
        #expect(hostsSource.contains("lastFallbackDNSRefreshSucceeded = result.didRefreshDNSCache"))
        #expect(hostsSource.contains("DNS was refreshed by the privileged fallback operation"))
        #expect(dnsSource.contains("try await killMDNSResponder()"))
        #expect(dnsSource.contains("throw DNSServiceError.flushFailed(\"mDNSResponder HUP exited with code"))
        let hupRange = try #require(dnsSource.range(of: "try await killMDNSResponder()"))
        let dateRange = try #require(dnsSource.range(of: "lastFlushDate = Date()"))
        #expect(hupRange.lowerBound < dateRange.lowerBound)
        #expect(!helperSource.contains("try? killProcess.run()"))
    }
}

@Suite("Customer UI Manifest Policy Tests")
struct CustomerUIManifestPolicyTests {
    @Test("Bulk entry actions require visual evidence")
    func bulkEntryActionsRequireVisualEvidence() throws {
        let testURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let repoRoot = packageRoot.deletingLastPathComponent()
        let manifest = try String(contentsOf: repoRoot.appendingPathComponent("Tests/CustomerUIActions.yml"))

        guard let bulkStart = manifest.range(of: "- id: bulk-entry-actions"),
              let settingsStart = manifest.range(of: "- id: settings-license-about-update-support")
        else {
            Issue.record("Customer UI manifest is missing the expected bulk/settings action boundaries")
            return
        }

        let bulkBlock = manifest[bulkStart.lowerBound ..< settingsStart.lowerBound]
        #expect(bulkBlock.contains("required_evidence_types:"))
        #expect(bulkBlock.contains("- screenshot"))
        #expect(bulkBlock.contains("- fixture"))
        #expect(bulkBlock.contains("- state_receipt"))
    }
}
