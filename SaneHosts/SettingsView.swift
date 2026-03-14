import SaneHostsFeature
import SaneUI
import SwiftUI
#if !APP_STORE
    import Sparkle
#endif

private enum SaneHostsSettingsTab: String, SaneSettingsTab {
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
    #if !APP_STORE
        let updater: SPUUpdater
    #endif
    var licenseService: LicenseService

    var body: some View {
        SaneSettingsContainer(defaultTab: SaneHostsSettingsTab.general) { tab in
            switch tab {
            case .general:
                #if !APP_STORE
                    GeneralSettingsTab(updater: updater)
                #else
                    GeneralSettingsTab()
                #endif
            case .license:
                LicenseSettingsTabContent(licenseService: licenseService)
            case .about:
                AboutTab()
            }
        }
    }
}

struct GeneralSettingsTab: View {
    @AppStorage("hideDockIcon") private var hideDockIcon = !SaneBackgroundAppDefaults.showDockIcon
    @State private var showFeedback = false
    #if !APP_STORE
        let updater: SPUUpdater
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CompactSection("Startup", icon: "power", iconColor: .orange) {
                    SaneLoginItemToggle()
                    CompactDivider()
                    SaneDockIconToggle(showDockIcon: showDockIconBinding)
                    CompactDivider()
                    Text("If you hide the Dock icon, SaneHosts stays available from the menu bar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }

                #if !APP_STORE
                    CompactSection("Software Updates", icon: "arrow.triangle.2.circlepath", iconColor: .saneAccent) {
                        SaneSparkleRow(
                            automaticallyChecks: Binding(
                                get: { updater.automaticallyChecksForUpdates },
                                set: { updater.automaticallyChecksForUpdates = $0 }
                            ),
                            checkFrequency: Binding(
                                get: { SaneSparkleCheckFrequency.resolve(updateCheckInterval: updater.updateCheckInterval) },
                                set: { updater.updateCheckInterval = $0.interval }
                            ),
                            onCheckNow: { updater.checkForUpdates() }
                        )
                    }
                #endif

                CompactSection("Support", icon: "lifepreserver", iconColor: .pink) {
                    HStack(spacing: 8) {
                        Button {
                            showFeedback = true
                        } label: {
                            Label("Report a Bug", systemImage: "ladybug")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Link(destination: featureRequestURL) {
                            Label("Request a Feature", systemImage: "lightbulb")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                    CompactDivider()

                    HStack(spacing: 8) {
                        Link(destination: issuesURL) {
                            Label("View Issues", systemImage: "arrow.up.right.square")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Link(destination: URL(string: "mailto:hi@saneapps.com")!) {
                            Label("Contact Support", systemImage: "envelope")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showFeedback) {
            SaneFeedbackView(
                diagnosticsService: .shared,
                extraAttachments: [("shield.lefthalf.filled", "Profile state, helper status, and startup settings")]
            )
        }
        .onAppear {
            #if !APP_STORE
                updater.updateCheckInterval = SaneSparkleCheckFrequency.normalizedInterval(from: updater.updateCheckInterval)
            #endif
        }
    }

    private var showDockIconBinding: Binding<Bool> {
        Binding(
            get: { !hideDockIcon },
            set: { hideDockIcon = !$0 }
        )
    }

    private var issuesURL: URL {
        URL(string: "https://github.com/sane-apps/SaneHosts/issues")!
    }

    private var featureRequestURL: URL {
        URL(string: "https://github.com/sane-apps/SaneHosts/issues/new?template=feature_request.md")!
    }
}

private struct LicenseSettingsTabContent: View {
    var licenseService: LicenseService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LicenseSettingsView(licenseService: licenseService, style: .panel)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
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
    #if !APP_STORE
        return [
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
    #else
        return []
    #endif
}()
