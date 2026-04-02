import Foundation

enum SaneHostsSettingsCopy {
    static let startupDockIconHint = String(
        localized: "sanehosts.settings.startup.dock_icon_hint",
        defaultValue: "If you hide the Dock icon, SaneHosts stays available from the menu bar."
    )

    static let updateAutomaticallyLabel = String(
        localized: "sanehosts.settings.updates.automatically_label",
        defaultValue: "Check for updates automatically"
    )

    static let updateAutomaticallyHint = String(
        localized: "sanehosts.settings.updates.automatically_hint",
        defaultValue: "Periodically check for new versions"
    )

    static let updateFrequencyLabel = String(
        localized: "sanehosts.settings.updates.frequency_label",
        defaultValue: "Check frequency"
    )

    static let updateFrequencyHint = String(
        localized: "sanehosts.settings.updates.frequency_hint",
        defaultValue: "Choose how often automatic update checks run"
    )

    static let checkNowButtonTitle = String(
        localized: "sanehosts.settings.updates.check_now_button",
        defaultValue: "Check Now"
    )

    static let checkingButtonTitle = String(
        localized: "sanehosts.settings.updates.checking_button",
        defaultValue: "Checking..."
    )

    static let checkNowHint = String(
        localized: "sanehosts.settings.updates.check_now_hint",
        defaultValue: "Check for updates right now"
    )

    static let feedbackAttachmentLabel = String(
        localized: "sanehosts.settings.about.feedback_attachment",
        defaultValue: "Profile state, helper status, and startup settings"
    )
}
