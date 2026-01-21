import SwiftUI

// MARK: - Tutorial State

@MainActor
@Observable
public class TutorialState {
    public static let shared = TutorialState()

    public var currentStep: TutorialStep = .none
    public var isActive: Bool = false

    // Anchor positions for UI elements (set by views)
    public var importButtonFrame: CGRect = .zero
    public var activateButtonFrame: CGRect = .zero

    private init() {}

    public func startTutorial() {
        isActive = true
        currentStep = .importBlocklist
    }

    public func advanceToActivate() {
        currentStep = .activateProfile
    }

    public func completeTutorial() {
        currentStep = .complete
        isActive = false
        // Mark as completed in UserDefaults
        UserDefaults.standard.set(true, forKey: "hasCompletedTutorial")
    }

    public func skipTutorial() {
        currentStep = .none
        isActive = false
        UserDefaults.standard.set(true, forKey: "hasCompletedTutorial")
    }

    public static var hasCompletedTutorial: Bool {
        UserDefaults.standard.bool(forKey: "hasCompletedTutorial")
    }
}

public enum TutorialStep {
    case none
    case importBlocklist
    case activateProfile
    case complete
}

// MARK: - Coach Mark Overlay

public struct CoachMarkOverlay: View {
    @Bindable var tutorial: TutorialState
    let windowFrame: CGRect

    public init(tutorial: TutorialState, windowFrame: CGRect) {
        self.tutorial = tutorial
        self.windowFrame = windowFrame
    }

    public var body: some View {
        if tutorial.isActive && tutorial.currentStep != .none && tutorial.currentStep != .complete {
            ZStack {
                // Dimmed background with cutout
                SpotlightBackground(
                    highlightFrame: currentHighlightFrame,
                    cornerRadius: 12
                )

                // Tooltip
                CoachMarkTooltip(
                    step: tutorial.currentStep,
                    highlightFrame: currentHighlightFrame,
                    windowFrame: windowFrame,
                    onNext: handleNext,
                    onSkip: { tutorial.skipTutorial() }
                )
            }
            .ignoresSafeArea()
        }
    }

    private var currentHighlightFrame: CGRect {
        switch tutorial.currentStep {
        case .importBlocklist:
            return tutorial.importButtonFrame
        case .activateProfile:
            return tutorial.activateButtonFrame
        default:
            return .zero
        }
    }

    private func handleNext() {
        switch tutorial.currentStep {
        case .importBlocklist:
            // Don't advance here - wait for import to complete
            // The import sheet will advance when done
            break
        case .activateProfile:
            tutorial.completeTutorial()
        default:
            break
        }
    }
}

// MARK: - Spotlight Background (Dimmed with Cutout)

struct SpotlightBackground: View {
    let highlightFrame: CGRect
    let cornerRadius: CGFloat

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                // Fill entire area with semi-transparent black
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .color(.black.opacity(0.75))
                )

                // Cut out the highlight area
                if highlightFrame != .zero {
                    let expandedFrame = highlightFrame.insetBy(dx: -8, dy: -8)
                    let cutoutPath = Path(roundedRect: expandedFrame, cornerRadius: cornerRadius + 4)
                    context.blendMode = .destinationOut
                    context.fill(cutoutPath, with: .color(.white))
                }
            }
            .compositingGroup()
        }
        .allowsHitTesting(false) // Let clicks through to the highlighted element
    }
}

// MARK: - Coach Mark Tooltip

struct CoachMarkTooltip: View {
    let step: TutorialStep
    let highlightFrame: CGRect
    let windowFrame: CGRect
    let onNext: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            Text(titleForStep)
                .font(.system(size: 18, weight: .semibold))

            // Description
            Text(descriptionForStep)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Buttons
            HStack(spacing: 12) {
                Button("Skip Tutorial") {
                    onSkip()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.system(size: 14))

                Spacer()

                if step == .importBlocklist {
                    Text("Click the button above")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else {
                    Button("Got it!") {
                        onNext()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(20)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .position(tooltipPosition)
    }

    private var titleForStep: String {
        switch step {
        case .importBlocklist:
            return "Start by Importing a Blocklist"
        case .activateProfile:
            return "Activate Your Profile"
        default:
            return ""
        }
    }

    private var descriptionForStep: String {
        switch step {
        case .importBlocklist:
            return "Click here to import a curated blocklist. We recommend starting with one of the popular ad-blocking lists."
        case .activateProfile:
            return "Your blocklist is ready! Click Activate to start blocking ads and trackers. You'll need to enter your password once."
        default:
            return ""
        }
    }

    private var tooltipPosition: CGPoint {
        guard highlightFrame != .zero else {
            return CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        }

        // Position tooltip below the highlighted element
        let tooltipWidth: CGFloat = 320
        let tooltipHeight: CGFloat = 140
        let padding: CGFloat = 20

        var x = highlightFrame.midX
        var y = highlightFrame.maxY + padding + tooltipHeight / 2

        // Keep tooltip within window bounds
        let minX = tooltipWidth / 2 + 20
        let maxX = windowFrame.width - tooltipWidth / 2 - 20
        x = min(max(x, minX), maxX)

        // If tooltip would go off bottom, position it above
        if y + tooltipHeight / 2 > windowFrame.height - 20 {
            y = highlightFrame.minY - padding - tooltipHeight / 2
        }

        return CGPoint(x: x, y: y)
    }
}

// MARK: - Preference Key for Anchor Frames

struct ImportButtonFrameKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct ActivateButtonFrameKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

// MARK: - View Extension for Tutorial Anchors

extension View {
    public func importButtonAnchor() -> some View {
        self.background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        TutorialState.shared.importButtonFrame = geometry.frame(in: .global)
                    }
                    .onChange(of: geometry.frame(in: .global)) { _, newFrame in
                        TutorialState.shared.importButtonFrame = newFrame
                    }
            }
        )
    }

    public func activateButtonAnchor() -> some View {
        self.background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        TutorialState.shared.activateButtonFrame = geometry.frame(in: .global)
                    }
                    .onChange(of: geometry.frame(in: .global)) { _, newFrame in
                        TutorialState.shared.activateButtonFrame = newFrame
                    }
            }
        )
    }
}
