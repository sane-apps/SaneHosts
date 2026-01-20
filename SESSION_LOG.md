# SaneHosts Session Log

## Session Summary - 2026-01-19 (FIX SESSION)

### Root Cause Identified & Fixed

**The blank UI was caused by the app sandbox preventing access to `/etc/hosts`.**

In `ProfileStore.load()`, the call to `loadSystemHosts()` reads `/etc/hosts`:
```swift
let content = try String(contentsOf: systemHostsURL, encoding: .utf8)  // /etc/hosts
```

With sandbox enabled, this throws a permission error. The error was caught but caused `loadProfiles()` to be skipped, resulting in an empty `profiles` array and blank UI.

### Fix Applied

**File:** `Config/SaneHosts.entitlements`

Changed:
```xml
<key>com.apple.security.app-sandbox</key>
<true/>
```

To:
```xml
<key>com.apple.security.app-sandbox</key>
<false/>
```

The app requires unsandboxed access to:
1. Read `/etc/hosts` for system entries
2. Write to `/etc/hosts` for profile activation (via AppleScript with admin privileges)

### Verification

After rebuilding with sandbox disabled:
- ✅ App launches correctly
- ✅ Profiles load and display in sidebar
- ✅ Adding entries works and UI updates immediately (BUG-001 fix confirmed working)
- ✅ Entry shows in detail view with correct stats

### BUG-001 Status

The UI reactivity bug (selectedProfile not updating) was **already fixed** in the codebase:
- `MainView.swift` now uses `selectedProfileID: UUID?` with a computed `selectedProfile` property
- This ensures fresh data is always fetched from the store

### Files Modified This Session

- `Config/SaneHosts.entitlements` - Disabled sandbox

### SOP Compliance: 9/10
- ✅ Read error messages and logs carefully
- ✅ Investigated root cause before attempting fixes
- ✅ Made minimal targeted change (single file)
- ✅ Verified fix with UI testing
- ⚠️ Could have checked entitlements earlier (was in CLAUDE.md notes)

---

## Previous Session - 2026-01-18

### What Was Attempted
- Rewrote RemoteSyncService to use URLSessionDownloadDelegate for progress tracking
- Added ImportPhase enum for tracking download/parse phases
- Added "Downloaded" badge for already-imported sources in RemoteImportSheet
- Added createRemote() method to ProfileStore
- Simplified download to use basic URLSession.shared.download()

### Files Modified
- RemoteSyncService.swift - multiple rewrites, currently has unused DownloadProgressDelegate class
- MainView.swift - added isSourceDownloaded() helper, FetchProgressOverlay with phase-based display
- ProfileStore.swift - added createRemote() method, added debug logging

---

## Session Summary - 2026-01-19 (DISTRIBUTION PREP & TESTING)

### Accomplishments
1. **Verified Custom URL Import**: Created an integration test to confirm that custom URL imports work correctly, including handling multiple hostnames per line.
2. **Verified Menu Bar Logic**: Inspected code to confirm 'Show in menu bar' toggle works via AppStorage binding and ProfileStore/HostsService logic is sound.
3. **Implemented Keyboard Shortcuts**: Added `Cmd+Shift+A` (Activate) and `Cmd+Shift+D` (Deactivate) to `MainView.swift` and removed non-functional placeholder shortcuts from `SaneHostsApp.swift`.
4. **Git Cleanup**: Updated `.gitignore` to exclude `build/` directory which was accidentally tracked, ensuring a cleaner repo state.

### Files Modified
- `SaneHostsPackage/Sources/SaneHostsFeature/Views/MainView.swift`: Added shortcuts.
- `SaneHosts/SaneHostsApp.swift`: Removed placeholder shortcuts.
- `.gitignore`: Added `build/`.
- `SaneHostsPackage/Tests/SaneHostsFeatureTests/CustomImportIntegrationTests.swift`: New test file.

### Notarization
- Still In Progress (Submission ID: 9df5f544-1176-40f1-99b6-0cce0c5772ea)
### Fix Applied (Post-Handoff)
- Added `com.apple.security.cs.disable-library-validation` to `Config/SaneHosts.entitlements` to fix crash on launch due to Hardened Runtime and library validation failure with ad-hoc signing.

