import SwiftUI

public struct ContentView: View {
    var licenseService: LicenseService
    @State private var tutorial = TutorialState.shared
    @State private var windowFrame: CGRect = .zero

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                MainView(licenseService: licenseService)

                // Tutorial overlay
                if tutorial.isActive {
                    CoachMarkOverlay(tutorial: tutorial, windowFrame: windowFrame)
                }
            }
            .onAppear {
                windowFrame = geometry.frame(in: .global)
                if !TutorialState.hasCompletedTutorial {
                    tutorial.startTutorial()
                }
            }
            .onChange(of: geometry.size) { _, _ in
                windowFrame = geometry.frame(in: .global)
            }
        }
    }

    public init(licenseService: LicenseService) {
        self.licenseService = licenseService
    }
}

// Convenience initializer for previews
public extension ContentView {
    init() {
        licenseService = LicenseService(
            appName: "SaneHosts",
            checkoutURL: URL(string: "https://go.saneapps.com/buy/sanehosts")!
        )
    }
}
