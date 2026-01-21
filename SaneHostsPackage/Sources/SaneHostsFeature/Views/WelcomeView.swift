import SwiftUI

/// Welcome onboarding view shown on first launch
public struct WelcomeView: View {
    @State private var currentPage = 0
    let onComplete: () -> Void

    public init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Page content
            TabView(selection: $currentPage) {
                WelcomePage()
                    .tag(0)

                WhatIsHostsPage()
                    .tag(1)

                PhilosophyPage()
                    .tag(2)

                GetStartedPage(onComplete: onComplete)
                    .tag(3)
            }
            .tabViewStyle(.automatic)

            // Navigation dots and buttons
            HStack {
                if currentPage > 0 {
                    Button("Back") {
                        withAnimation {
                            currentPage -= 1
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                } else {
                    Spacer()
                        .frame(width: 60)
                }

                Spacer()

                // Page indicators
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(currentPage == index ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }

                Spacer()

                if currentPage < 3 {
                    Button("Next") {
                        withAnimation {
                            currentPage += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Spacer()
                        .frame(width: 60)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 30)
        }
        .frame(width: 600, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Welcome Page

private struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "globe.americas.fill")
                .font(.system(size: 80))
                .foregroundStyle(.linearGradient(
                    colors: [.blue, .cyan],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            Text("Welcome to SaneHosts")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Take control of what your Mac connects to")
                .font(.title3)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "shield.checkered", text: "Block ads and trackers at the system level")
                FeatureRow(icon: "slider.horizontal.3", text: "Create profiles for different purposes")
                FeatureRow(icon: "lock.shield", text: "100% local - your data stays on your Mac")
            }
            .padding(.top, 20)

            Spacer()
        }
        .padding(40)
    }
}

// MARK: - What is Hosts Page

private struct WhatIsHostsPage: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text("What is a hosts file?")
                .font(.largeTitle)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 16) {
                ExplainerRow(
                    number: "1",
                    title: "Your Mac checks it first",
                    description: "Before connecting anywhere, macOS checks /etc/hosts to see if you've defined a custom address."
                )

                ExplainerRow(
                    number: "2",
                    title: "Block by redirecting",
                    description: "By pointing ad servers to 0.0.0.0 (nowhere), those connections fail silently. No ads load."
                )

                ExplainerRow(
                    number: "3",
                    title: "Works everywhere",
                    description: "Unlike browser extensions, this works in every app on your Mac - browsers, games, even system apps."
                )
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .padding(40)
    }
}

// MARK: - Philosophy Page

private struct PhilosophyPage: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("Built for a Sound Mind")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("\"For God has not given us a spirit of fear, but of power and of love and of a sound mind.\"")
                .font(.body)
                .italic()
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text("2 Timothy 1:7")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 20) {
                PillarCard(
                    icon: "bolt.fill",
                    color: .yellow,
                    title: "Power",
                    subtitle: "Agency",
                    description: "Your data stays on your device. No cloud, no accounts."
                )

                PillarCard(
                    icon: "heart.fill",
                    color: .pink,
                    title: "Love",
                    subtitle: "Function",
                    description: "Built to serve, not extract. No dark patterns."
                )

                PillarCard(
                    icon: "brain.head.profile",
                    color: .purple,
                    title: "Sound Mind",
                    subtitle: "Form",
                    description: "Calm, focused interface. No anxiety."
                )
            }
            .padding(.top, 10)

            Spacer()
        }
        .padding(40)
    }
}

// MARK: - Get Started Page

private struct GetStartedPage: View {
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text("You're Ready!")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Here's what you can do next:")
                .font(.title3)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 16) {
                NextStepRow(
                    icon: "plus.circle.fill",
                    color: .blue,
                    title: "Create a profile",
                    description: "Start with a blank profile and add your own entries"
                )

                NextStepRow(
                    icon: "arrow.down.circle.fill",
                    color: .green,
                    title: "Import a blocklist",
                    description: "Choose from curated ad-blocking and privacy lists"
                )

                NextStepRow(
                    icon: "doc.on.doc.fill",
                    color: .orange,
                    title: "Use a template",
                    description: "Pre-configured profiles for common use cases"
                )
            }
            .padding(.horizontal, 20)

            Spacer()

            Button(action: onComplete) {
                Text("Get Started")
                    .font(.headline)
                    .frame(width: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
                .frame(height: 20)
        }
        .padding(40)
    }
}

// MARK: - Helper Views

private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 30)

            Text(text)
                .font(.body)
        }
    }
}

private struct ExplainerRow: View {
    let number: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(number)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.accentColor)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct PillarCard: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let description: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(color)

            Text(title)
                .font(.headline)

            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(description)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

private struct NextStepRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(color)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    WelcomeView(onComplete: {})
}
