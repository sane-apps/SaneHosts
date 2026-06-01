# Changelog

All notable changes to SaneHosts will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.15] - 2026-06-01

Enables the 30-day Pro trial for direct-download users so first-run onboarding and Basic/Pro gating match the shared license flow.

---

## [1.1.15] - 2026-06-01

Enables the 30-day Pro trial for direct-download users so first-run onboarding and Basic/Pro gating match the shared SaneUI license model.

---

## [1.1.14] - 2026-05-25

Fixes the first-run tutorial overlay and Tahoe dark-mode readability, reduces launch memory for very large saved profiles, and hardens remote import, activation, deactivation, export, duplicate, merge, and DNS-refresh paths so profile state stays consistent under heavier use.

---

## [1.1.13] - 2026-05-25

Improves Tahoe readability, keeps the included Basic profile available, and prevents long IP addresses from wrapping in the Entries table.

---

## [1.1.12] - 2026-05-19

Fixes license-key paste reliability in activation and settings.

---

## [1.1.11] - 2026-05-09

Improves first-launch and settings navigation reliability, keeps direct-download install handling consistent, and verifies release signing before launch.

---

## [1.1.10] - 2026-05-09

Adds the macOS utility app category to release metadata so system and distribution checks classify SaneHosts correctly.

---

## [1.1.9] - 2026-05-05

Hardens remote blocklist imports, hosts file validation, local profile storage permissions, and helper fallback paths. Clarifies privacy disclosures while keeping hosts data local, and refreshes Basic/Pro UI copy so release surfaces stay readable, privacy-first, and consistent.

---

## [1.1.8] - 2026-04-15

Updates Pro pricing screens so onboarding and upgrade prompts consistently show the current $14.99 one-time unlock, and refreshes release metadata for the direct-download channel.

---

## [1.1.7] - 2026-04-09

Fixes Settings routing from the menu bar and Dock so the settings window reopens reliably.

---

## [1.1.5] - 2026-03-14

Shared settings layout now matches the rest of the app.
Added in-app diagnostics-backed bug reporting.
Improved direct license activation reliability and messaging.
Fixed the release build failure caused by duplicate app icon resources.

---

## [1.1.6] - 2026-03-28

Fixed menu bar and Dock navigation so SaneHosts opens reliably from a cold start.
Standardized Settings, About, and License screens for a cleaner and more readable layout.
Improved bug reporting, update controls, and overall polish across the app.

---

## [1.1.3] - 2026-03-04

Improved onboarding interaction reliability in Basic.

---

## [1.1.2] - 2026-03-04

Fix Essentials startup lockout in free mode; improve startup selection reliability; harden update/release channel integrity checks.

---

## [Unreleased]

### Added
- Product screenshots on website and README
- 14-perspective documentation audit with security fixes
- SaneProcess hooks for session management
- Centralized support email (hi@saneapps.com)

### Fixed
- Logger subsystem standardized to `com.mrsane.SaneHosts` across all services
- Force unwraps replaced with guard-let / nil coalescing (ProfileStore, ProfilePresets, MainView)
- `print()` replaced with `os_log` throughout codebase
- Website icon updated
- Tracked binary coverage file (`default.profraw`) removed from git

## [1.0.0] - 2026-01-21

### Added

#### Core
- Profile management (create, read, update, delete) with JSON file persistence
- Entry management (add, edit, delete, toggle) within profiles
- Profile activation via AppleScript with administrator privileges
- Automatic DNS cache flush after hosts file changes
- Data persistence in `~/Library/Application Support/SaneHosts/`
- Existing `/etc/hosts` entries auto-imported on first run

#### Protection Levels
- 5 curated protection tiers: Essentials, Balanced, Strict, Aggressive, Kitchen Sink
- Each tier bundles appropriate blocklists from 200+ curated sources
- Guided onboarding with coach mark tutorial for first-time users
- Welcome flow with philosophy page

#### Import & Export
- Remote URL import from 200+ curated blocklists (Steven Black, Hagezi, AdGuard, OISD, etc.)
- 10+ blocklist categories (ads, trackers, malware, social, adult, gambling, etc.)
- Custom URL import for any hosts-format blocklist
- Merge profiles with automatic hostname deduplication
- Export profiles as standard `.hosts` format files
- Smart auto-naming for combined blocklist imports
- URL health checks with visual availability indicators
- Domain-only blocklist format support

#### Bulk Operations
- Bulk enable/disable entries via selection mode
- Bulk delete selected entries
- Duplicate profiles
- Profile drag-to-reorder in sidebar

#### Menu Bar
- Menu bar icon with network status indicator
- Active profile name display
- Quick profile switcher dropdown
- One-click activate/deactivate from menu bar
- Hide Dock icon option (menu-bar-only mode)

#### UI & Polish
- Native SwiftUI design system with dark mode support
- App icon (dark blue gradient with cyan network symbol)
- Keyboard shortcuts (Cmd+N, Cmd+I, Cmd+E, Cmd+D, Cmd+M, Cmd+Shift+A, Cmd+Shift+D)
- Source freshness indicator (days since last sync)
- Entry count display on profiles in sidebar
- Search and filter across large profiles (handles 100K+ entries)
- Color-coded profile types (blue for remote, purple for merged)
- Dock menu with Settings and Open actions
- Full menu system (New Profile, Import Blocklist, Deactivate All)

#### Performance & Reliability
- Optimized for 100K+ entry profiles with single-pass counting
- 300ms search debouncing for large datasets
- Background thread DNS flush
- Crash resilience with automatic backup/recovery (3 backups per profile)
- Background thread profile loading to prevent launch hangs
- NotificationCenter sync replacing 1-second polling

#### Security
- Hosts file modifications require admin authentication
- Touch ID / LocalAuthentication support (with AppleScript fallback)
- XPC protocol scaffold for privileged helper
- Comment newline injection sanitization
- HTTPS warning for HTTP blocklist URLs
- Hardened runtime enabled
- Code signed and notarized by Apple
- DEBUG bypass for auth in debug builds

#### Distribution
- Sparkle auto-update framework integration
- Unified release command (`./scripts/SaneMaster.rb release`)
- Appcast generator (`scripts/generate_appcast.sh`)
- Landing page website
- Privacy policy page
- GitHub repository at github.com/sane-apps/SaneHosts

### Fixed
- IP filtering: `RemoteSyncService` no longer rejects valid non-loopback IPs
- Bulk operations: single disk write instead of one per entry
- Menu bar state: shared `ProfileStore` singleton replaces separate instance
- Deactivate now properly updates `ProfileStore` state
- Atomic writes for `createRemote` in `ProfileStore`
- Parser instance reuse during large imports (was creating 100K+ instances)
- App icon sizes corrected for all asset catalog slots
- 6 broken blocklist URLs replaced (OISD discontinuation, 404s, 403s)
- Settings window accessible from Dock and Menu Bar
- Launch crash with disable-library-validation entitlement

### Security
- Hosts file modifications require admin authentication
- No network access except for remote hosts import
- All data stored locally in Application Support

[Unreleased]: https://github.com/sane-apps/SaneHosts/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/sane-apps/SaneHosts/releases/tag/v1.0.0
