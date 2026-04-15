# Research Cache

Persistent research findings for this project. Limit: 200 lines.
Graduate verified findings to ARCHITECTURE.md or DEVELOPMENT.md.

<!-- Sections added by research agents. Format:
## Topic Name
**Updated:** YYYY-MM-DD | **Status:** verified/stale/partial | **TTL:** 7d/30d/90d
**Source:** tool or URL
- Finding 1
- Finding 2
-->

## SwiftUICore Package-Test Linker Block | Updated: 2026-04-15 | Status: verified | TTL: 7d

### Sources

- Docs: local `infra/SaneProcess/scripts/sanemaster/verify.rb` disabled-test fallback behavior
- Web: current Apple/Swift community reports for Xcode 16 Swift Package test runs linking through `SwiftUICore`
- GitHub: no SaneHosts-specific upstream fix found that avoids the current linker restriction cleanly
- Local: Mini `./scripts/SaneMaster.rb verify --quiet`, Mini `xcodebuild test -project SaneHosts.xcodeproj -scheme SaneHosts -only-testing:SaneHostsFeatureTests`, and local package/test-plan inspection

### Findings

- The blocker is the package-test lane, not the signed app build or the direct-download product.
- Mini `verify --quiet` currently reaches `swift test --package-path SaneHostsPackage --filter SaneHostsFeatureTests` and fails with `cannot link directly with 'SwiftUICore' because product being built is not an allowed client of it`.
- Switching to plain `xcodebuild test -only-testing:SaneHostsFeatureTests` is not a clean workaround because that package test target is not a member of the app scheme's test plan.
- The shared verifier already has a sanctioned fallback for this exact class of issue: skip the broken test lane, build the main app, and document the reason until Apple/Xcode stops tripping the linker restriction.
