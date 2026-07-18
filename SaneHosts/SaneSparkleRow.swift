// Direct-distribution only: Sparkle UI must remain app-local so it never ships
// through a non-direct SaneUI consumer.

#if !APP_STORE && !SETAPP

import SaneUI
import SwiftUI

enum SaneSparkleCheckFrequency: String, CaseIterable, Identifiable {
    case daily
    case weekly

    var id: String { rawValue }

    var interval: TimeInterval {
        switch self {
        case .daily: 60 * 60 * 24
        case .weekly: 60 * 60 * 24 * 7
        }
    }

    static func resolve(updateCheckInterval: TimeInterval) -> Self {
        let threshold = (Self.daily.interval + Self.weekly.interval) / 2
        return updateCheckInterval >= threshold ? .weekly : .daily
    }

    static func normalizedInterval(from updateCheckInterval: TimeInterval) -> TimeInterval {
        resolve(updateCheckInterval: updateCheckInterval).interval
    }
}

struct SaneSparkleRow: View {
    @Binding private var automaticallyChecks: Bool
    @Binding private var checkFrequency: SaneSparkleCheckFrequency
    private let isAvailable: Bool
    private let unavailableStatus: String?
    private let onCheckNow: () -> Void
    @State private var isChecking = false

    init(
        automaticallyChecks: Binding<Bool>,
        checkFrequency: Binding<SaneSparkleCheckFrequency>,
        isAvailable: Bool = true,
        unavailableStatus: String? = nil,
        onCheckNow: @escaping () -> Void
    ) {
        _automaticallyChecks = automaticallyChecks
        _checkFrequency = checkFrequency
        self.isAvailable = isAvailable
        self.unavailableStatus = unavailableStatus
        self.onCheckNow = onCheckNow
    }

    var body: some View {
        if let unavailableStatus, !isAvailable {
            CompactRow("Status") {
                Text(unavailableStatus)
                    .font(.system(size: 13, weight: .medium))
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CompactDivider()
        }

        CompactToggle(label: "Check for updates automatically", isOn: $automaticallyChecks)
            .help("Periodically check for new versions")
            .disabled(!isAvailable)

        CompactDivider()

        CompactRow("Check frequency") {
            Picker("", selection: $checkFrequency) {
                Text("Daily").tag(SaneSparkleCheckFrequency.daily)
                Text("Weekly").tag(SaneSparkleCheckFrequency.weekly)
            }
            .pickerStyle(.segmented)
            .frame(width: 170)
            .disabled(!isAvailable || !automaticallyChecks)
        }
        .help("Choose how often automatic update checks run")

        CompactDivider()

        CompactRow("Actions") {
            Button(isChecking ? "Checking..." : "Check Now") {
                guard !isChecking else { return }
                isChecking = true
                onCheckNow()

                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(5))
                    isChecking = false
                }
            }
            .buttonStyle(SaneActionButtonStyle())
            .disabled(isChecking || !isAvailable)
            .help(isAvailable ? "Check for updates right now" : (unavailableStatus ?? "Check for updates right now"))
        }
    }
}

#endif
