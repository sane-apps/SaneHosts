import SwiftUI

public struct ContentView: View {
    @Binding var hasSeenWelcome: Bool
    var licenseService: LicenseService
    @State private var tutorial = TutorialState.shared
    @State private var windowFrame: CGRect = .zero

    public var body: some View {
        if hasSeenWelcome {
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
                }
                .onChange(of: geometry.size) { _, _ in
                    windowFrame = geometry.frame(in: .global)
                }
            }
        } else {
            WelcomeView {
                withAnimation {
                    hasSeenWelcome = true
                }
                // Start tutorial after welcome if not completed
                if !TutorialState.hasCompletedTutorial {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        tutorial.startTutorial()
                    }
                }
            }
        }
    }

    public init(hasSeenWelcome: Binding<Bool>, licenseService: LicenseService) {
        _hasSeenWelcome = hasSeenWelcome
        self.licenseService = licenseService
    }
}

// Convenience initializer for previews
public extension ContentView {
    init() {
        _hasSeenWelcome = .constant(true)
        licenseService = LicenseService(
            appName: "SaneHosts",
            checkoutURL: URL(string: "https://go.saneapps.com/buy/sanehosts")!
        )
    }
}
