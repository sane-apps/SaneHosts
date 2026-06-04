import AppKit
import SaneUI
import SwiftUI
import UniformTypeIdentifiers

struct RemoteImportSheet: View {
    let store: ProfileStore
    let onCreated: (Profile) -> Void

    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    // Selection state - pre-select recommended blocklists for better UX
    @State var selectedSources: Set<String> = Set(BlocklistCatalog.recommended.map(\.id))
    @State var profileName = ""
    @State var previousSuggestedName = "" // Track auto-filled value to detect user edits
    @State var expandedCategories: Set<BlocklistCategory> = [.recommended, .adsTrackers]

    // Import state
    @State var isImporting = false
    @State var importProgress: Double = 0
    @State var currentImportName = ""
    @State var error: String?
    @State var importTask: Task<Void, Never>?
    @State var urlCheckTask: Task<Void, Never>?

    // Custom URL
    @State var showingCustomURL = false
    @State var customURL = ""

    // URL liveness checking
    @State var urlStatus: [String: URLCheckStatus] = [:]
    @State var isCheckingURLs = false

    enum URLCheckStatus: Equatable {
        case checking
        case available
        case unavailable(Int) // HTTP status code
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            Divider()

            // Scrollable content
            ScrollView {
                VStack(spacing: 16) {
                    // Categories with blocklists
                    ForEach(BlocklistCatalog.availableCategories, id: \.self) { category in
                        categorySection(category)
                    }

                    // Custom URL option
                    customURLSection
                }
                .padding(20)
            }

            Divider()

            // Footer with actions
            footer
                .padding(20)
        }
        .frame(width: 520, height: 600)
        .background(SaneGradientBackground())
        .overlay {
            if isImporting {
                importProgressOverlay
            }
        }
        .onChange(of: selectedSources) { _, newValue in
            // Auto-fill name when selection changes (only if user hasn't typed a custom name)
            if !newValue.isEmpty, profileName.isEmpty || profileName == previousSuggestedName {
                profileName = suggestedName
                previousSuggestedName = suggestedName
            }
        }
        .onChange(of: customURL) { _, newValue in
            // Auto-fill name when custom URL changes (only if user hasn't typed a custom name)
            if !newValue.isEmpty, profileName.isEmpty || profileName == previousSuggestedName {
                profileName = suggestedName
                previousSuggestedName = suggestedName
            }
        }
        .onAppear {
            checkAllURLs()
            // Auto-fill profile name based on pre-selected recommended sources
            if !selectedSources.isEmpty, profileName.isEmpty {
                profileName = suggestedName
                previousSuggestedName = suggestedName
            }
        }
        .onDisappear {
            urlCheckTask?.cancel()
            urlCheckTask = nil
            if importTask != nil {
                cancelImport()
            }
        }
    }
}
