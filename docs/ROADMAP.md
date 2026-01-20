# SaneHosts Roadmap

## Competitive Analysis

### Gas Mask (Open Source)
- Combined files (merge multiple sources) ← unique feature
- Remote URL sync with configurable intervals
- Syntax highlighting
- Tray icon with quick switch
- **Weakness**: Old codebase, dated UI, no Touch ID

### Helm (App Store)
- Clean modern UI
- Auto DNS flush
- Preview functionality
- **Weakness**: Basic features, no remote sources, no Touch ID

### PowerToys Hosts Editor (Windows)
- Users want: batch editing, import/export, save confirmation
- **Weakness**: Windows only

### Pi-hole (Network-level)
- Group management (different rules for different devices)
- Categorized blocklists (ads, trackers, social, malware)
- Dashboard with stats
- **Weakness**: Requires dedicated hardware/server

### SaneHosts Differentiators
1. **Touch ID** - First macOS hosts manager with biometric auth
2. **Modern SwiftUI** - Native, fast, beautiful
3. **Smart Categories** - Auto-categorize imports (ads, social, trackers)
4. **Menu Bar Quick Toggle** - One-click activate/deactivate
5. **Profile Scheduling** - Time-based activation (Phase 3)

---

## Phase 1 (COMPLETE)
Core functionality - basic hosts file management

- [x] Profile CRUD (create, read, update, delete)
- [x] Entry management (add, edit, delete, toggle)
- [x] Profile activation via AppleScript admin auth
- [x] Remote URL import (Steven Black lists, etc.)
- [x] DNS flush after activation
- [x] Data persistence
- [x] SwiftUI design system (SaneClip style)
- [x] Disable sandbox for /etc/hosts access

---

## Phase 2 (MOSTLY COMPLETE)
Authentication, Menu Bar & Polish

### 2.1 Touch ID Authentication
Replace AppleScript password prompt with Touch ID:

- [x] Create privileged helper tool scaffold (LaunchDaemon)
- [x] Implement XPC protocol between app and helper
- [x] Add LocalAuthentication (LAContext) for Touch ID/password
- [ ] Helper writes to /etc/hosts with root privileges (falls back to AppleScript)
- [x] Graceful fallback to password if Touch ID unavailable
- [ ] Register helper with SMAppService

### 2.2 Menu Bar App
Quick access without opening main window:

- [x] Menu bar icon (status indicator - shows network icon)
- [x] Show active profile name
- [x] Quick profile switcher dropdown
- [x] One-click activate/deactivate
- [ ] "Block Mode" toggle (activates blocking profile)

### 2.3 Bulk Operations & Import
Features users requested:

- [x] Bulk enable/disable entries (selection mode)
- [x] Bulk delete entries
- [ ] Import from text/csv file
- [ ] Export profile to shareable format
- [x] Duplicate profile

### 2.4 Debug/Testing Support
- [x] Add DEBUG bypass for auth (auto-succeed in debug builds)
- [ ] Dry-run mode to preview /etc/hosts changes
- [ ] Unit tests with mocked HostsService

### 2.5 UI Polish
- [ ] App icon design
- [x] Keyboard shortcuts (Cmd+Shift+A activate, Cmd+Shift+D deactivate)
- [ ] Entry drag-and-drop reordering
- [x] Source freshness indicator (days since last sync)
- [ ] Entry count badge on profiles

### 2.6 Distribution (COMPLETE)
See `docs/DISTRIBUTION.md` for full release checklist.

- [x] Generate Sparkle EdDSA keys (in keychain, public key: `QwXgCpqQfcdZJ6BIzLRrBmn2D7cwkNbaniuIkm/DJyQ=`)
- [x] Sparkle feed URL configured (`https://sanehosts.com/appcast.xml`)
- [x] Build release script (`scripts/build_release.sh`)
- [x] Appcast generator (`scripts/generate_appcast.sh`)
- [x] Website template (`website/index.html`, `website/privacy.html`)
- [ ] Purchase domain (sanehosts.com)
- [ ] Create GitHub repo (github.com/sane-apps/SaneHosts)
- [ ] First release (v1.0)

---

## Phase 3 (FUTURE)
Advanced Features

### 3.1 Scheduling
- [ ] Time-based profile activation (e.g., block social media 9-5)
- [ ] Calendar integration

### 3.2 Sync
- [ ] iCloud sync for profiles
- [ ] Export/import profiles as files

### 3.3 Intelligence
- [ ] Auto-categorize imported hosts (ads, trackers, social, etc.)
- [ ] Conflict detection between profiles
- [ ] Hosts file health check

### 3.4 Network
- [ ] Per-network profiles (auto-activate on home WiFi)
- [ ] VPN-aware activation

---

## Architecture Notes

### Privileged Helper Pattern (Phase 2.1)

```
┌─────────────────┐     XPC      ┌──────────────────────┐
│   SaneHosts     │◄────────────►│  SaneHostsHelper     │
│   (main app)    │              │  (LaunchDaemon)      │
│                 │              │  - runs as root      │
│  LAContext      │              │  - writes /etc/hosts │
│  (Touch ID)     │              │  - flushes DNS       │
└─────────────────┘              └──────────────────────┘
```

1. App requests auth via LAContext (Touch ID prompt)
2. If auth succeeds, app sends hosts content via XPC
3. Helper validates request, writes to /etc/hosts
4. Helper flushes DNS cache
5. Helper returns success/failure to app

### Files to Create
- `SaneHostsHelper/` - New target for privileged helper
- `SaneHostsHelper/main.swift` - Helper entry point
- `SaneHostsHelper/HostsWriter.swift` - File writing logic
- `SaneHostsHelper/Info.plist` - LaunchDaemon config
- `SaneHostsHelper/SaneHostsHelper-Launchd.plist` - launchd plist
- `Shared/XPCProtocol.swift` - Shared protocol for XPC
