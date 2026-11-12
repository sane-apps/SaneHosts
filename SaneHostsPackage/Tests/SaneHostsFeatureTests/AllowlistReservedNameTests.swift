import Foundation
@testable import SaneHostsFeature
import Testing

@Suite("Allowlist reserved names")
struct AllowlistReservedNameTests {
    @Test("Names that describe this Mac can never be allowed")
    func reservedNamesRejected() {
        var allowlist = HostAllowlist()
        for name in ["localhost", "ip6-localhost", "IP6-Loopback", "broadcasthost", "local"] {
            let added = allowlist.add(name)
            #expect(!added, "\(name) should be rejected")
        }
        #expect(allowlist.isEmpty)
        let addedNormal = allowlist.add("ads.example.com")
        #expect(addedNormal)
    }

    @Test("A loopback line in a profile survives the allowlist")
    func loopbackLineSurvives() {
        var allowlist = HostAllowlist()
        _ = allowlist.add("ip6-localhost")
        let entries = [HostEntry(ipAddress: "::1", hostnames: ["ip6-localhost"])]
        #expect(allowlist.apply(to: entries).flatMap(\.hostnames) == ["ip6-localhost"])
    }
}
