#if os(macOS) && !APP_STORE && !SETAPP
    import Foundation
    import SaneUI

    /// Direct-download support link. The shared library ships no title or
    /// destination of its own, so the direct build supplies them at launch.
    /// Without this the About screen loses its Donate row.
    public enum SaneHostsDirectSupport {
        @MainActor
        public static func install() {
            SaneDirectSupportCopy.current = SaneDirectSupportCopy(
                buttonTitle: "Donate",
                buttonHelp: "Donate on GitHub Sponsors",
                accessibilityLabel: "Donate",
                destinationURL: URL(string: "https://github.com/sponsors/MrSaneApps")!,
                aboutRowTitle: "Donate",
                freeAppTitle: "This app is free now",
                freeAppDetail: "Every feature stays unlocked. Donate only if you want to support it.",
                welcomeIncludedDetail: "Every feature is included. Setup stays the same. Donate only if you want to support it.",
                expiredOpenSourceDetail: "SaneApps open-sourced this app. Every feature stays unlocked. Donate only if you want to support it.",
                expiredCardTitle: "Donate",
                expiredCardSubtitle: "Optional. The app stays free."
            )
        }
    }
#endif
