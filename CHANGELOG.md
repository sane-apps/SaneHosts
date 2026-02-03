# Changelog

All notable changes to SaneHosts will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
