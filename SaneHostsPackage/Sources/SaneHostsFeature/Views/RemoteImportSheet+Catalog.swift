import AppKit
import SaneUI
import SwiftUI
import UniformTypeIdentifiers

extension RemoteImportSheet {
    // MARK: - URL Liveness Checking

    func checkAllURLs() {
        guard urlStatus.isEmpty else { return } // Only check once per sheet open

        isCheckingURLs = true

        // Mark all as checking
        for source in BlocklistCatalog.all {
            urlStatus[source.id] = .checking
        }

        urlCheckTask?.cancel()
        urlCheckTask = Task {
            let sources = BlocklistCatalog.all
            let concurrencyLimit = 6
            var nextIndex = 0

            await withTaskGroup(of: (String, URLCheckStatus).self) { group in
                func enqueueNext() {
                    guard nextIndex < sources.count else { return }
                    let source = sources[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        guard !Task.isCancelled else { return (source.id, .unavailable(0)) }
                        let status = await checkURL(source.url)
                        return (source.id, status)
                    }
                }

                for _ in 0 ..< min(concurrencyLimit, sources.count) {
                    enqueueNext()
                }

                for await (id, status) in group {
                    if Task.isCancelled {
                        group.cancelAll()
                        break
                    }
                    await MainActor.run {
                        urlStatus[id] = status
                    }
                    enqueueNext()
                }
            }

            await MainActor.run {
                isCheckingURLs = false
                urlCheckTask = nil
            }
        }
    }

    func checkURL(_ url: URL) async -> URLCheckStatus {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if (200 ... 399).contains(httpResponse.statusCode) {
                    return .available
                } else {
                    return .unavailable(httpResponse.statusCode)
                }
            }
            return .available
        } catch {
            return .unavailable(0) // Network error
        }
    }

    // MARK: - Header

    var header: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title)
                    .foregroundStyle(.blue)
                Text("Import Blocklists")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()

                // URL checking status
                if isCheckingURLs {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Checking URLs...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                    }
                } else {
                    let unavailableCount = urlStatus.values.filter {
                        if case .unavailable = $0 { return true }
                        return false
                    }.count

                    if unavailableCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.orange)
                            Text("\(unavailableCount) unavailable")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                }
            }

            Text("Select one or more blocklists to import. Multiple selections will be merged into a single profile.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Category Section

    func categorySection(_ category: BlocklistCategory) -> some View {
        let sources = BlocklistCatalog.sources(for: category)
        let isExpanded = expandedCategories.contains(category)
        let selectedInCategory = sources.filter { selectedSources.contains($0.id) }.count

        return VStack(spacing: 0) {
            // Category header (clickable to expand/collapse)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedCategories.remove(category)
                    } else {
                        expandedCategories.insert(category)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: category.icon)
                        .font(.body)
                        .foregroundStyle(categoryColor(category))
                        .frame(width: 24)

                    Text(category.rawValue)
                        .fontWeight(.medium)
                        .foregroundColor(.white)

                    if selectedInCategory > 0 {
                        Text("\(selectedInCategory)")
                            .font(.system(size: 13, weight: .semibold))
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(categoryColor(category).opacity(0.2))
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(isExpanded ? "Collapse" : "Expand") \(category.rawValue)")
            .accessibilityHint("\(sources.count) blocklists, \(selectedInCategory) selected")

            // Blocklist items (when expanded)
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(sources) { source in
                        blocklistRow(source)
                        if source.id != sources.last?.id {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .background(colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    func blocklistRow(_ source: BlocklistSource) -> some View {
        let isSelected = selectedSources.contains(source.id)
        let status = urlStatus[source.id]
        let isUnavailable = if case .unavailable = status { true } else { false }

        return Button {
            guard !isUnavailable else { return } // Don't allow selecting unavailable sources

            if isSelected {
                selectedSources.remove(source.id)
            } else {
                selectedSources.insert(source.id)
            }
        } label: {
            HStack(spacing: 12) {
                // Checkbox
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.blue : Color.white.opacity(isUnavailable ? 0.9 : 1))

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(source.name)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.white)

                        if source.isRecommended, !isUnavailable {
                            Text("Recommended")
                                .font(.system(size: 13, weight: .semibold))
                                .fontWeight(.semibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.2))
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                    }

                    Text(source.description)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(2)
                }

                Spacer()

                // Entry count estimate
                Text(source.estimatedEntries)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.saneAccent.opacity(0.28))
                    .clipShape(Capsule())

                // URL status indicator
                urlStatusBadge(for: status)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isUnavailable ? 0.92 : 1.0)
        .accessibilityLabel("\(source.name), \(isSelected ? "selected" : "not selected")\(isUnavailable ? ", unavailable" : "")")
        .accessibilityHint(isUnavailable ? "This blocklist is currently unavailable" : "Double-tap to \(isSelected ? "deselect" : "select") this blocklist")
    }

    @ViewBuilder
    func urlStatusBadge(for status: URLCheckStatus?) -> some View {
        switch status {
        case .checking:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 20, height: 20)
        case .available:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.green)
        case let .unavailable(code):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
                if code > 0 {
                    Text("\(code)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                }
            }
        case .none:
            EmptyView()
        }
    }

    // MARK: - Custom URL Section

    var customURLSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation {
                    showingCustomURL.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "link")
                        .font(.body)
                        .foregroundStyle(.blue)
                        .frame(width: 24)

                    Text("Custom URL")
                        .fontWeight(.medium)
                        .foregroundColor(.white)

                    Spacer()

                    Image(systemName: showingCustomURL ? "chevron.down" : "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showingCustomURL ? "Hide custom URL input" : "Show custom URL input")

            if showingCustomURL {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField("https://example.com/hosts.txt", text: $customURL)
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(colorScheme == .dark ? Color.black.opacity(0.2) : Color.white)
                            .cornerRadius(6)
                    }

                    // HTTPS requirement
                    if customURL.lowercased().hasPrefix("http://") {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.orange)
                            Text("Only HTTPS URLs are supported.")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    func categoryColor(_ category: BlocklistCategory) -> Color {
        switch category {
        case .recommended: .saneWarning
        case .adsTrackers: .saneAccent
        case .malwareSecurity: .saneError
        case .privacy: .indigo
        case .socialMedia: .blue
        case .gambling: .yellow
        case .fakeNews: .brown
        case .adult: .gray
        case .annoyances: .mint
        case .regional: .cyan
        }
    }
}
