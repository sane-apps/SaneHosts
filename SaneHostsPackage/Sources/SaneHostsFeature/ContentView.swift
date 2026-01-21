import SwiftUI

public struct ContentView: View {
    @Binding var hasSeenWelcome: Bool
    @State private var showingWelcome = false

    public var body: some View {
        MainView()
            .sheet(isPresented: $showingWelcome) {
                WelcomeView {
                    hasSeenWelcome = true
                    showingWelcome = false
                }
            }
            .onAppear {
                if !hasSeenWelcome {
                    showingWelcome = true
                }
            }
    }

    public init(hasSeenWelcome: Binding<Bool>) {
        self._hasSeenWelcome = hasSeenWelcome
    }
}

// Convenience initializer for previews
extension ContentView {
    public init() {
        self._hasSeenWelcome = .constant(true)
    }
}
