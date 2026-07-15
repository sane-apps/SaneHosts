# SaneHosts Agent Instructions

Follow `~/AGENTS.md` first (cross-LLM policy source of truth). This file carries SaneHosts-specific facts.

Philosophy: `~/SaneApps/meta/Brand/NORTH_STAR.md`

## What Is This

SaneHosts is a macOS app for managing the `/etc/hosts` file through profiles:

- Choose from 5 **Protection Levels** (Essentials → Kitchen Sink) with curated preset blocklists
- Create and manage host blocking profiles
- Import from 200+ curated blocklists across 10+ categories
- Activate/deactivate profiles with admin authentication
- Flush DNS cache automatically
- First-run **coach mark tutorial** guides new users through activation

**Key architecture note**: the app writes `/etc/hosts` through the privileged XPC helper when available. Direct builds can fall back to a validated AppleScript admin prompt if the helper is unavailable.

**Pricing**: Basic is free; Pro is $14.99 one-time. Direct download only — no App Store lane.

## Source Of Truth

- Development workflow: `DEVELOPMENT.md`
- Architecture: `ARCHITECTURE.md`
- Privacy/security claims: `PRIVACY.md`, `SECURITY.md`
- Release checklist: `docs/DISTRIBUTION.md`
- Current session context / manual UI test plan: `SESSION_HANDOFF.md`

Product roster (canonical): macOS = SaneHosts, SaneClip, SaneClick, SaneSales, SaneVideo; iOS = SaneScan (iPhone/iPad only), SaneLot; SaaS = SaneCite. SaneBar is retired (free + OSS, never advertised as a peer product).

## Project Structure

| Path | Purpose |
|------|---------|
| `SaneHosts.xcworkspace` | **Open this** — workspace with app + SPM package |
| `SaneHosts/` | App target (minimal — just entry point) |
| `SaneHostsPackage/Sources/SaneHostsFeature/Models/` | Data models (Profile, HostEntry) |
| `SaneHostsPackage/Sources/SaneHostsFeature/Services/` | Business logic services |
| `SaneHostsPackage/Sources/SaneHostsFeature/Views/` | SwiftUI views |
| `SaneHostsPackage/Tests/SaneHostsFeatureTests/` | Unit tests (models, parser, mocked services) |
| `Config/` | Build configurations |
| `docs/` | Documentation + website |

Admin operations: look for `do shell script` with `administrator privileges`.

## Key Services

| Service | Purpose |
|---------|---------|
| `HostsService` | Reads/writes `/etc/hosts` via helper or admin-privileged AppleScript |
| `ProfileStore` | Profile CRUD, JSON file persistence, activation state management |
| `DNSService` | Flushes DNS cache after hosts file changes |
| `RemoteSyncService` | Imports hosts from remote URLs |
| `HostsParser` | Parses hosts file format |
| `ProfilePresets` | 5-tier protection level definitions with curated blocklist bundles |
| `BlocklistCatalog` | 200+ curated blocklist sources across 10+ categories |

## Security Considerations

- **Admin authentication**: hosts file modifications require macOS authentication
- **Privileged helper**: uses SMAppService/XPC helper for root hosts writes when available
- **AppleScript fallback**: direct builds can use a validated admin prompt fallback
- **Validation**: hosts content is validated before helper or fallback writes

Known limitations:

1. **AppleScript auth** — password prompt for each activation (XPC helper remembers)
2. **No sandbox** — required to write `/etc/hosts`; hardened runtime + Developer ID signing still apply for notarization

## Build, Test, Release (Mini-first)

- Canonical route: run `ruby scripts/SaneMaster.rb verify` on the Mac Mini (build + tests).
- Local Xcode builds on the Air are an explicitly-approved fallback only.
- Release: `bash ~/SaneApps/infra/SaneProcess/scripts/release.sh --project <path> --full` (ships ZIPs). Follow `docs/DISTRIBUTION.md`; do not run manual R2 or Pages deploy commands for normal releases.
- Sparkle keys, notarytool profile, Team ID, and other shared credentials: see `~/SaneApps/infra/SaneProcess/DEVELOPER_SETUP.md` (shared across all SaneApps — do not regenerate).

## Research & Memory

- Past bugs/learnings: agentmemory `memory_recall` / `memory_smart_search` + Claude file memory. Serena is code-navigation only; its old memories are absorbed into agentmemory.
- Apple frameworks: `apple-docs` MCP. Library docs: `plugin:context7:context7` (resolve-library-id → query-docs). GitHub search: `gh` CLI.
- Verify platform APIs exist before coding against them (NSAppleScript privilege elevation, SMAppService/XPC helper interfaces, `dscacheutil` for DNS flush).
