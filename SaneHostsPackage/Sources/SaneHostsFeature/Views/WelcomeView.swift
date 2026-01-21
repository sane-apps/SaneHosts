import SwiftUI
import AppKit

/// Welcome onboarding view shown on first launch
/// Marketing pitch: Threat → Barrier → Solution → Promise
public struct WelcomeView: View {
    @State private var currentPage = 0
    let onComplete: () -> Void
    private let totalPages = 5

    public init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Page content
            Group {
                switch currentPage {
                case 0:
                    WelcomePage()
                case 1:
                    ThreatPage()
                case 2:
                    BarrierPage()
                case 3:
                    SolutionPage()
                case 4:
                    SanePromisePage(onComplete: onComplete)
                default:
                    WelcomePage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Page indicators
            HStack(spacing: 8) {
                ForEach(0..<totalPages, id: \.self) { index in
                    Circle()
                        .fill(currentPage == index ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, 20)

            // Bottom Controls
            HStack {
                if currentPage > 0 {
                    Button("Back") {
                        withAnimation {
                            currentPage -= 1
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 15))
                }

                Spacer()

                if currentPage < totalPages - 1 {
                    Button("Next") {
                        withAnimation {
                            currentPage += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") {
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 30)
        }
        .frame(width: 700, height: 520)
        .background(OnboardingBackground())
    }
}

// MARK: - Background

private struct OnboardingBackground: View {
    var body: some View {
        ZStack {
            VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow)

            LinearGradient(
                colors: [
                    Color.indigo.opacity(0.08),
                    Color.blue.opacity(0.05),
                    Color.indigo.opacity(0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Page 1: Welcome

private struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 24) {
            if let appIcon = NSApp.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 128, height: 128)
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
            }

            Text("Welcome to SaneHosts")
                .font(.system(size: 32, weight: .bold))

            Text("Take control of what your Mac connects to.")
                .font(.system(size: 18))

            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "shield.checkered", color: .blue, text: "Block ads and trackers system-wide")
                FeatureRow(icon: "slider.horizontal.3", color: .purple, text: "Create profiles for different purposes")
                FeatureRow(icon: "lock.shield", color: .green, text: "100% local - your data stays on your Mac")
            }
            .padding(.top, 8)
        }
        .padding(40)
    }
}

// MARK: - Page 2: The Threat

private struct ThreatPage: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "eye.trianglebadge.exclamationmark")
                .font(.system(size: 64))
                .foregroundStyle(.red)

            Text("The Threat")
                .font(.system(size: 28, weight: .bold))

            Text("Every time you use your Mac, hidden connections reach out to ad networks, trackers, and data collectors.")
                .font(.system(size: 17))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)

            Text("They track what you browse, what apps you use, and build profiles about you — all without your knowledge or consent.")
                .font(.system(size: 17))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
                .padding(.top, 4)
        }
        .padding(40)
    }
}

// MARK: - Page 3: The Barrier

private struct BarrierPage: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "xmark.shield")
                .font(.system(size: 64))
                .foregroundStyle(.orange)

            Text("The Barriers")
                .font(.system(size: 28, weight: .bold))

            VStack(alignment: .leading, spacing: 20) {
                BarrierRow(
                    number: "1",
                    title: "The DIY Way",
                    description: "Your Mac has a hosts file that can block trackers. But you'd need Terminal, admin commands, and thousands of manual entries. One typo breaks your internet."
                )

                BarrierRow(
                    number: "2",
                    title: "The Alternatives",
                    description: "Other apps exist, but they track you too, require subscriptions, or phone home with your data. You're trading one tracker for another."
                )
            }
            .frame(maxWidth: 520)
        }
        .padding(40)
    }
}

private struct BarrierRow: View {
    let number: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.orange)
                .frame(width: 28, height: 28)
                .background(Color.orange.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                Text(description)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Page 4: The Sane Solution

private struct SolutionPage: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("The Sane Solution")
                .font(.system(size: 28, weight: .bold))

            VStack(alignment: .leading, spacing: 20) {
                SolutionSection(
                    number: "1",
                    title: "Simple, Not Scary",
                    description: "No Terminal. No commands. Import blocklists with one click, activate with another. If something breaks, just deactivate.",
                    color: .green
                )

                SolutionSection(
                    number: "2",
                    title: "Private, Not Exploitative",
                    description: "100% local. No accounts. No subscriptions. No telemetry. Your data never leaves your Mac.",
                    color: .blue
                )
            }
            .frame(maxWidth: 520)
        }
        .padding(40)
    }
}

private struct SolutionSection: View {
    let number: String
    let title: String
    let description: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                Text(description)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Page 5: Our Sane Promise

private struct SanePromisePage: View {
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("Our Sane Philosophy")
                .font(.system(size: 32, weight: .bold))

            VStack(spacing: 8) {
                Text("\"For God has not given us a spirit of fear,")
                    .font(.system(size: 17))
                    .italic()
                Text("but of power and of love and of a sound mind.\"")
                    .font(.system(size: 17))
                    .italic()
                Text("— 2 Timothy 1:7")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            HStack(spacing: 20) {
                PillarCard(
                    icon: "bolt.fill",
                    color: .yellow,
                    title: "Power",
                    description: "Your data stays on your device. No cloud, no tracking."
                )

                PillarCard(
                    icon: "heart.fill",
                    color: .pink,
                    title: "Love",
                    description: "Built to serve you. No dark patterns or manipulation."
                )

                PillarCard(
                    icon: "brain.head.profile",
                    color: .purple,
                    title: "Sound Mind",
                    description: "Calm, focused design. No clutter or anxiety."
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .padding(32)
    }
}

// MARK: - Helper Views

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(color)
                .frame(width: 32)

            Text(text)
                .font(.system(size: 17))
        }
    }
}

private struct SolutionRow: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(color)
                .frame(width: 32)

            Text(text)
                .font(.system(size: 17))
        }
    }
}

private struct PillarCard: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(color)

            Text(title)
                .font(.system(size: 18, weight: .semibold))

            Text(description)
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 14)
        .background(Color.primary.opacity(0.08))
        .cornerRadius(12)
    }
}

#Preview {
    WelcomeView(onComplete: {})
}
