import AppKit
import SaneHostsFeature
import SwiftUI
import Sparkle

enum SaneHostsSettingsTab: String, SaneSettingsTab {
    case general = "General"
    case license = "License"
    case about = "About"

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .license: "key.fill"
        case .about: "info.circle"
        }
    }

    var iconColor: Color {
        switch self {
        case .general: .secondary
        case .license: .yellow
        case .about: .blue
        }
    }
}

struct SaneHostsSettingsView: View {
    let updater: SPUUpdater?
    let updateEligibility: SaneUpdateEligibility
    var licenseService: LicenseService
    @State private var selectedTab: SaneHostsSettingsTab?

    var body: some View {
        SaneSettingsContainer(
            defaultTab: SaneHostsSettingsTab.general,
            selection: $selectedTab
        ) { tab in
            switch tab {
            case .general:
                GeneralSettingsTab(updater: updater, updateEligibility: updateEligibility)
            case .license:
                LicenseSettingsTabContent(licenseService: licenseService)
            case .about:
                AboutTab()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSettingsTab)) { notification in
            if let tab = notification.object as? SaneHostsSettingsTab {
                selectedTab = tab
            }
        }
    }
}

struct GeneralSettingsTab: View {
    @AppStorage("hideDockIcon") private var hideDockIcon = !SaneBackgroundAppDefaults.showDockIcon
    let updater: SPUUpdater?
    let updateEligibility: SaneUpdateEligibility
    @State private var automaticallyChecksForUpdates = false
    @State private var updateCheckFrequency = SaneSparkleCheckFrequency.daily

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CompactSection("Startup", icon: "power", iconColor: .orange) {
                    SaneLoginItemToggle()
                    CompactDivider()
                    SaneDockIconToggle(showDockIcon: showDockIconBinding)
                    CompactDivider()
                    Text("If you hide the Dock icon, SaneHosts stays available from the menu bar.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }

                CompactSection("Software Updates", icon: "arrow.triangle.2.circlepath", iconColor: .saneAccent) {
                    SaneSparkleRow(
                        automaticallyChecks: Binding(
                            get: { automaticallyChecksForUpdates },
                            set: { newValue in
                                automaticallyChecksForUpdates = newValue
                                updater?.automaticallyChecksForUpdates = newValue
                            }
                        ),
                        checkFrequency: Binding(
                            get: { updateCheckFrequency },
                            set: { newValue in
                                updateCheckFrequency = newValue
                                updater?.updateCheckInterval = newValue.interval
                            }
                        ),
                        isAvailable: updateEligibility.canUseInAppUpdates && updater != nil,
                        unavailableStatus: updateEligibility.userFacingStatus,
                        onCheckNow: {
                            guard updateEligibility.canUseInAppUpdates, let updater else {
                                NSSound.beep()
                                return
                            }
                            updater.checkForUpdates()
                        }
                    )
                }

            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            automaticallyChecksForUpdates = updater?.automaticallyChecksForUpdates ?? false
            let interval = updater?.updateCheckInterval ?? SaneUI.SaneSparkleCheckFrequency.daily.interval
            updateCheckFrequency = SaneUI.SaneSparkleCheckFrequency.resolve(updateCheckInterval: interval)
            updater?.updateCheckInterval = SaneUI.SaneSparkleCheckFrequency.normalizedInterval(from: interval)
        }
    }

    private var showDockIconBinding: Binding<Bool> {
        Binding(
            get: { !hideDockIcon },
            set: { hideDockIcon = !$0 }
        )
    }
}

private struct LicenseSettingsTabContent: View {
    var licenseService: LicenseService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LicenseSettingsView(licenseService: licenseService, style: .panel)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 460, alignment: .leading)
        }
    }
}

struct AboutTab: View {
    var body: some View {
        SaneAboutView(
            appName: "SaneHosts",
            githubRepo: "SaneHosts",
            diagnosticsService: .shared,
            licenses: saneHostsLicenses,
            feedbackExtraAttachments: [("shield.lefthalf.filled", "Profile state, helper status, and startup settings")]
        )
    }
}

private let saneHostsLicenses: [SaneAboutView.LicenseEntry] = {
    [
        SaneAboutView.LicenseEntry(
            name: "Sparkle",
            url: "https://sparkle-project.org",
            text: """
            Copyright (c) 2006-2013 Andy Matuschak.
            Copyright (c) 2009-2013 Elgato Systems GmbH.

            Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

            The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

            THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
            """
        )
    ]
}()
