# SaneHosts Session Handoff

> Updated: 2026-01-19 2:30 PM
> Status: **AWAITING NOTARIZATION** - GitHub repo created, notarization pending

## Latest: Release Pipeline Execution (2026-01-19 2:30 PM)

### GitHub Repo Created ✅
- **URL**: https://github.com/stephanjoseph/SaneHosts
- All code pushed to main branch

### Notarization Pending ⏳
- **Submission ID**: `9df5f544-1176-40f1-99b6-0cce0c5772ea`
- **Status**: In Progress (may take hours or fail)
- **Previous failure**: Missing hardened runtime (now fixed)

### Build Config Fixed ✅
- Added `ENABLE_HARDENED_RUNTIME = YES` to Shared.xcconfig
- Added `com.apple.security.automation.apple-events` to entitlements
- Fixed build_release.sh to skip spctl before notarization

### When Notarization Completes

**If Accepted:**
```bash
# Staple the ticket
xcrun stapler staple build/SaneHosts-1.0.dmg

# Move to releases
mkdir -p releases
mv build/SaneHosts-1.0.dmg releases/
shasum -a 256 releases/SaneHosts-1.0.dmg > releases/SaneHosts-1.0.dmg.sha256

# Generate appcast
./scripts/generate_appcast.sh

# Create GitHub release
VERSION=1.0
gh release create "v${VERSION}" "releases/SaneHosts-${VERSION}.dmg" \
  --title "SaneHosts ${VERSION}" \
  --notes "Initial release"
```

**If Rejected:**
```bash
# Check the log
xcrun notarytool log 9df5f544-1176-40f1-99b6-0cce0c5772ea --keychain-profile "notarytool"

# Fix issues, rebuild
./scripts/build_release.sh
```

### Touch ID Status
- AuthenticationService.swift: Touch ID code implemented
- HostsService.swift: Falls back to AppleScript (helper not registered)
- SaneHostsHelper/: Code exists but not built/registered with SMAppService
- **Current behavior**: Password prompt via AppleScript (works, not ideal)

---

## Previous: Distribution Pipeline Complete (2026-01-19 2:10 PM)

### Distribution Infrastructure ✅
Full release pipeline created. See `docs/DISTRIBUTION.md` for complete guide.

**Scripts Created:**
- `scripts/build_release.sh` - Archive, sign, notarize, create DMG
- `scripts/generate_appcast.sh` - Generate Sparkle appcast.xml feed
- `scripts/setup_sparkle_keys.sh` - Key setup (NOT NEEDED - key already exists)

**Website Created:**
- `website/index.html` - Landing page (dark theme, feature cards)
- `website/privacy.html` - Privacy policy

**CRITICAL - Sparkle Key Already Exists:**
- **Public Key**: `QwXgCpqQfcdZJ6BIzLRrBmn2D7cwkNbaniuIkm/DJyQ=`
- **Location**: macOS Keychain (account: ed25519)
- **Configured in**: `Config/Shared.xcconfig`

### Performance Optimizations ✅
Optimized for power users with 100K+ entry profiles:
- Replaced 1-second polling with NotificationCenter sync
- Single-pass entry counting (O(n) → single iteration)
- 300ms search debouncing
- DNS flush moved to background thread
- Crash resilience with automatic backup/recovery

### Icon Fix ✅
All PNG icons were 2x wrong dimensions. Fixed with `sips -z` resize.

### Git Commits Today:
```
9bbf4b8 feat: Add complete distribution pipeline
7de3b1b fix: Correct app icon sizes for asset catalog
d14a11e feat: Add crash resilience with backup and recovery system
79b1661 perf: Optimize for large datasets and improve responsiveness
```

---

## Previous: App Icon + Dock Menu (2026-01-19 12:55 PM)

### App Icon Created ✅
**Issue:** Dock showed generic Xcode icon - AppIcon.appiconset had empty slots
**Fix:** Created `sanehosts-icon.svg` following Sane Apps brand template:
- Dark blue gradient background (`#1a2744` → `#0d1525`)
- Cyan network/globe symbol (`#5fa8d3`) with glow effect
- Generated all required PNG sizes (16x16 through 512x512@2x)
- Updated Contents.json with filename references

**Files:**
- Source SVG: `/Users/sj/SaneApps/meta/Brand/Assets/sanehosts-icon.svg`
- Icons: `SaneHosts/Assets.xcassets/AppIcon.appiconset/`

### Dock Menu Added ✅
**Issue:** Right-clicking dock icon had no Settings option
**Fix:** Added `AppDelegate` with `applicationDockMenu()` method
- Settings... (Cmd+,) - Opens Settings window
- Open SaneHosts - Brings app to front

**Location:** `SaneHostsApp.swift` - AppDelegate class

---

## Previous: Menu Bar State Sync Fix (2026-01-19 12:45 PM)

### Menu Bar Fixes ✅
**Issues Found:**
1. MenuBarProfileStore created separate ProfileStore instance (state never synced)
2. Deactivate didn't update ProfileStore state
3. Silent error handling (try?) - users never saw failures
4. Dead code (MenuBarManager.swift) cluttering codebase

**Fixes Applied:**
1. Added `ProfileStore.shared` singleton for app-wide state sharing
2. MenuBarProfileStore now uses shared store with 1-second polling sync
3. Added proper error display in menu bar UI
4. Removed unused MenuBarManager.swift
5. Changed accent color from teal → indigo (distinct from blue)

**Location:** `SaneHostsApp.swift`, `ProfileStore.swift`

---

## Previous: Critical Bug Fixes (2026-01-19)

### 1. Data Loss Prevention ✅
**Issue:** On first run, existing user entries in `/etc/hosts` were not imported, leading to data loss when activating any profile.
**Fix:** Added `migrateExistingSystemHosts()` to `ProfileStore.swift`. On first run, the app now creates an "Existing Entries" profile containing all user-defined hosts entries.
**Location:** `ProfileStore.swift` lines 115-142

### 2. IP Filtering Bug Fixed ✅
**Issue:** `RemoteSyncService` hardcoded a filter for `0.0.0.0` and `127.0.0.1`, silently rejecting valid hosts entries with other IPs (e.g., `192.168.x.x`, `10.x.x.x`).
**Fix:** Replaced the hardcoded check with `HostsParser.isValidIPAddress()` to allow any valid IP.
**Location:** `RemoteSyncService.swift` lines 179-182

### 3. Bulk Operations Performance ✅
**Issue:** Bulk enable/disable/delete operations performed serial disk writes (one per entry), causing severe lag on large profiles.
**Fix:** Added `bulkUpdateEntries(ids:in:update:)` and `bulkRemoveEntries(ids:from:)` methods to `ProfileStore`. Refactored `ProfileDetailView` to use them for single-write operations.
**Location:** `ProfileStore.swift` lines 467-498, `ProfileDetailView.swift` lines 496-520

### 4. Independent Verification (12:30 PM)
All fixes audited and verified. Two additional issues found and fixed during verification:
1. **Missed Atomic Write:** `createRemote` in `ProfileStore` was not using `.atomic` option - FIXED
2. **Parser Hoisting:** `RemoteSyncService` was creating 100K+ `HostsParser` instances per import - FIXED
- **Test Result:** 43/43 unit tests passed

---

## Previous: URL Liveness Checking + Auto-Naming Fix

### 1. Fixed Broken Blocklist URLs
OISD discontinued HOSTS format on Jan 1, 2024. Fixed 6 broken URLs:
| Original | Issue | Replacement |
|----------|-------|-------------|
| OISD Basic | 404 | Hagezi Light |
| OISD NSFW | 404 | Anti-Porn HOSTS |
| First-Party Trackers | 404 | NextDNS CNAME Cloaking |
| Polish Ads Filter | 404 | Removed |
| Japanese Ads Filter | 403 | Removed |
| Korean Ads Filter | Mislabeled | Renamed to "No Google" |

### 2. URL Liveness Preflight Check (NEW)
When Import Blocklist sheet opens:
- Parallel HEAD requests check all ~45 URLs
- Shows "Checking URLs..." spinner in header
- ✓ Green badge for available sources
- ⚠️ Red badge + error code for unavailable
- Broken sources are grayed out and unselectable
- Header shows count of unavailable sources

### 3. Smart Auto-Naming for Combined Blocklists
Profile names now generated descriptively:
- 2-3 sources: `"Steven Black + Hagezi + Peter Lowe"`
- 4+ sources: `"Steven Black + 4 more"`

**Location:** `MainView.swift` - RemoteImportSheet, `BlocklistCatalog.swift`

## Completed This Session (2026-01-19)

### 1. UI Visibility Improvements (Dark Mode) ✅
- **Add Entry button**: Orange icon (distinct from blue/teal), `.subheadline` text
- **Last Fetched**: Readable `.primary.opacity(0.8)` text, larger FreshnessIndicator badge
- **StatCard icons**: Better color differentiation
- **Activate/Deactivate buttons**: Parity with `.borderedProminent` style

### 2. Color Semantics Finalized ✅
| Color | Meaning |
|-------|---------|
| **Blue** | Web/URL/remote content |
| **Orange** | Actions, call-to-action |
| **Green** | Active status ONLY |
| **Indigo** | App accent (saneAccent) - changed from teal |
| **Purple** | Merged profiles |
| **Red** | Destructive |

### 3. Import Blocklist Audit ✅
Full audit completed. Key findings:
- **50+ curated blocklists** in 10 categories
- **Auto-naming logic exists** but wasn't filling the field (now fixed)
- **Deduplication** works via hostname matching
- **Entry limit**: 500K entries (increased from 10K)
- **Profile refresh**: Source URL stored but no update mechanism yet

### 4. Previous Fixes ✅
- Multi-select delete from context menu
- Merge profiles auto-naming (generateMergedName)
- Profile copy naming ("Default 1", "Default 2")
- Entry cap increased to 500K

## Quick Commands

```bash
# Build
xcodebuild -workspace SaneHosts.xcworkspace -scheme SaneHosts -configuration Debug -arch arm64 build

# Launch with logging (SOP)
killall -9 SaneHosts 2>/dev/null; sleep 1
open "/Users/sj/Library/Developer/Xcode/DerivedData/SaneHosts-dflfxnlekfyjpqbckkiubgayrxgw/Build/Products/Debug/SaneHosts.app"

# Clear profiles
rm -rf ~/Library/Application\ Support/SaneHosts/Profiles/*.json
```

## Files Modified This Session

| File | Changes |
|------|---------|
| `SaneHostsApp.swift` | Menu bar state sync, error handling, dock menu via AppDelegate, teal→indigo |
| `MainView.swift` | URL liveness checking, smart auto-naming, import blocklist UI |
| `BlocklistCatalog.swift` | Fixed 6 broken URLs, removed dead sources |
| `ProfileDetailView.swift` | Add Entry (orange), Last Fetched visibility, StatCard colors |
| `ProfileStore.swift` | Entry limit 500K, shared singleton, bulk operations |
| `DesignSystem.swift` | Changed saneAccent from teal to indigo |
| `MenuBarManager.swift` | DELETED (unused legacy code) |
| `Assets.xcassets/AppIcon.appiconset/` | NEW: All icon sizes from sanehosts-icon.svg |
| `meta/Brand/Assets/sanehosts-icon.svg` | NEW: SaneHosts brand icon source |

## Profile Data Location

`~/Library/Application Support/SaneHosts/Profiles/`

---

## Import Blocklist Flow (Documented)

```
1. User clicks "Import Blocklist" → RemoteImportSheet opens
2. User selects from 50+ curated blocklists or enters custom URL
3. Profile Name auto-fills based on selection (NEW FIX)
4. Import → Download → Parse → Deduplicate → Save profile
5. Single source = .remote profile (blue)
6. Multiple sources = .merged profile (purple)
```

## Pending Testing

### Import Blocklist
- [x] Auto-naming fills text field
- [x] Smart combined naming ("A + B + C" or "A + 4 more")
- [x] URL liveness checking on sheet open
- [x] Broken sources grayed out
- [x] Single blocklist import works
- [x] Multiple blocklist merge works
- [x] Large files (146K entries) work without crash
- [ ] Custom URL import works

### Menu Bar (FIXED)
- [x] Menu bar state syncs with main window (1-second polling)
- [x] Error handling shows failures to user
- [x] Deactivate properly updates state
- [ ] Menu bar icon appears when "Show in menu bar" is enabled
- [ ] Activate/deactivate from menu bar works

### Other
- [x] Bulk Enable / Disable / Delete entries (bulk methods added)
- [ ] Keyboard shortcuts (Cmd+Shift+A, Cmd+Shift+D)
