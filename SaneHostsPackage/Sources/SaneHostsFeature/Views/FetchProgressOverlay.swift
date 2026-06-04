import AppKit
import SaneUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Fetch Progress Overlay

struct FetchProgressOverlay: View {
    let onCancel: () -> Void

    var syncService: RemoteSyncService { RemoteSyncService.shared }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // Phase-based progress display
                switch syncService.phase {
                case .connecting:
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Connecting...")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)

                case .downloading:
                    if !syncService.isIndeterminate {
                        // Determinate progress bar
                        ProgressView(value: syncService.downloadProgress)
                            .progressViewStyle(.linear)
                            .frame(width: 200)
                            .tint(.blue)

                        Text(String(format: "%.0f%%", syncService.downloadProgress * 100))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                    } else {
                        // Indeterminate - show downloaded bytes
                        ProgressView()
                            .scaleEffect(1.2)
                    }
                    Text(syncService.statusMessage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)

                case .parsing:
                    ProgressView(value: syncService.parseProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 200)
                        .tint(.orange)
                    Text(syncService.statusMessage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)

                case .saving:
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Saving...")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)

                case .complete:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.blue)
                    Text(syncService.statusMessage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)

                case .idle, .error:
                    ProgressView()
                        .scaleEffect(1.2)
                    Text(syncService.statusMessage.isEmpty ? "Connecting..." : syncService.statusMessage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }

                // Cancel button - always available during import
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(SaneActionButtonStyle())
                .accessibilityLabel("Cancel fetch")
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )
        }
    }
}
