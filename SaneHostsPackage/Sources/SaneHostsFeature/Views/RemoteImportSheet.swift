import AppKit
import SaneUI
import SwiftUI
import UniformTypeIdentifiers

struct RemoteImportSheet: View {
    let store: ProfileStore
    let onCreated: (Profile) -> Void

    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    @State var selectedSources: Set<String> = Set(BlocklistCatalog.recommended.map(\.id))
    @State var profileName = ""
    /// The last auto-filled name, so a name the user typed is never overwritten.
    @State var previousSuggestedName = ""
    @State var expandedCategories: Set<BlocklistCategory> = [.recommended, .adsTrackers]

    @State var isImporting = false
    @State var importProgress: Double = 0
    @State var currentImportName = ""
    @State var error: String?
    @State var importTask: Task<Void, Never>?
    @State var urlCheckTask: Task<Void, Never>?

    @State var showingCustomURL = false
    @State var customURL = ""
    @State var chosenFileURL: URL?

    @State var urlStatus: [String: URLCheckStatus] = [:]
    @State var isCheckingURLs = false

    enum URLCheckStatus: Equatable {
        case checking
        case available
        case unavailable(Int)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    ForEach(BlocklistCatalog.availableCategories, id: \.self) { category in
                        categorySection(category)
                    }

                    customURLSection
                }
                .padding(20)
            }

            Divider()

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
            if !newValue.isEmpty, profileName.isEmpty || profileName == previousSuggestedName {
                profileName = suggestedName
                previousSuggestedName = suggestedName
            }
        }
        .onChange(of: customURL) { _, newValue in
            if !newValue.isEmpty, profileName.isEmpty || profileName == previousSuggestedName {
                profileName = suggestedName
                previousSuggestedName = suggestedName
            }
        }
        .onAppear {
            checkAllURLs()
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
