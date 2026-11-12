import Foundation
@testable import SaneHostsFeature
import Testing

/// Network checks (liveness, size, freshness) live in scripts/check_blocklist_catalog.py.
@Suite("Blocklist catalog integrity")
struct CatalogIntegrityTests {
    @Test("Every list has a unique id and its own HTTPS URL")
    func idsAndURLsAreUnique() {
        let all = BlocklistCatalog.all
        #expect(Set(all.map(\.id)).count == all.count)
        #expect(Set(all.map(\.url)).count == all.count)
        #expect(all.allSatisfy { $0.url.scheme == "https" })
    }

    @Test("Every shown category has lists and every preset list exists")
    func categoriesAndPresetsResolve() {
        for category in BlocklistCatalog.availableCategories {
            #expect(!BlocklistCatalog.sources(for: category).isEmpty)
        }
        for preset in ProfilePreset.allCases {
            #expect(preset.blocklistSources.count == preset.blocklistSourceIds.count, "\(preset.displayName)")
        }
    }

    @Test("Size labels are numbers like 3.5K, 42K or 350")
    func estimatesAreNumeric() {
        let pattern = /^\d+(\.\d+)?K?$/
        for source in BlocklistCatalog.all {
            #expect(source.estimatedEntries.wholeMatch(of: pattern) != nil, "\(source.id): \(source.estimatedEntries)")
        }
    }
}
