# SaneHosts Testing Results

> Date: 2026-01-18
> Tester: Claude Code (automated UI testing)

## Summary

The app builds, launches, and core functionality works. One significant bug was found in UI reactivity.

## Test Results

### 1. App Launch & Basic UI
| Test | Status | Notes |
|------|--------|-------|
| App launches without crash | PASS | Builds and runs successfully |
| Main window appears | PASS | NavigationSplitView with sidebar |
| Sparkle auto-update prompt | PASS | Shows on first launch |
| Settings window opens | NOT TESTED | Manual test needed |

### 2. Profile Management
| Test | Status | Notes |
|------|--------|-------|
| Create new profile | PASS | "Test Profile" created successfully |
| Profile persists to disk | PASS | JSON saved to sandbox container |
| Delete profile | NOT TESTED | Context menu automation failed |
| Rename profile | NOT TESTED | Context menu automation failed |

### 3. Entry Management
| Test | Status | Notes |
|------|--------|-------|
| Add entry to profile | PASS | Entry saved to JSON (verified on disk) |
| Entry displays after restart | PASS | Shows 127.0.0.1 → test.local |
| Edit entry | NOT TESTED | Sheet automation incomplete |
| Delete entry | NOT TESTED | Context menu automation failed |
| Toggle enabled/disabled | NOT TESTED | |

### 4. Data Persistence
| Test | Status | Notes |
|------|--------|-------|
| Profiles saved to disk | PASS | ~/Library/Containers/com.mrsane.SaneHosts/... |
| Entries saved in profile JSON | PASS | Verified JSON structure |
| Data survives app restart | PASS | All data loads correctly |

### 5. Templates
| Test | Status | Notes |
|------|--------|-------|
| Template picker opens | BLOCKED | SwiftUI Menu/AppleScript incompatibility |

### 6. Remote Import
| Test | Status | Notes |
|------|--------|-------|
| Import from URL | BLOCKED | SwiftUI Menu/AppleScript incompatibility |

### 7. Profile Activation
| Test | Status | Notes |
|------|--------|-------|
| Activate profile | NOT TESTED | Requires admin auth |
| Writes to /etc/hosts | NOT TESTED | |
| Deactivate profile | NOT TESTED | |

### 8. Settings
| Test | Status | Notes |
|------|--------|-------|
| Settings persist | NOT TESTED | |

## Bugs Found

### BUG-001: UI Reactivity Issue (HIGH)

**Summary**: When adding entries to a profile, the UI doesn't update until the app is restarted.

**Root Cause**: In `MainView.swift`, `selectedProfile` is a `@State` variable holding a Profile struct (value type). When entries are added via the ProfileStore, the `selectedProfile` snapshot isn't updated.

**Evidence**:
- Added entry via AddEntrySheet
- UI continued showing "0 entries" and "No Entries" message
- Checked disk: Entry was saved correctly to JSON
- After app restart: Entry displayed correctly

**Fix Required**:
Change from:
```swift
@State private var selectedProfile: Profile?
// Used as: ProfileDetailView(profile: profile, ...)
```

To either:
1. Store only the ID and compute the profile from store each render
2. Use a computed property that fetches from store.profiles by ID
3. Make ProfileDetailView observe the store directly

**Priority**: HIGH - Core UX is broken for add/edit operations

## Automation Limitations

SwiftUI's `Menu` component doesn't expose its items properly via Accessibility APIs when used in toolbars. This blocked testing of:
- Template picker
- Remote import
- Context menus on profiles/entries

These features should be manually tested.

## Recommendations

1. **Fix BUG-001** before release - it's a critical UX issue
2. **Manual testing needed** for:
   - Template creation (Ad Blocking, Development, Social, Privacy)
   - Remote URL import
   - Profile activation with admin auth
   - Settings persistence
3. **Consider** adding keyboard shortcuts for common actions
4. **Generate Sparkle keys** before distribution

## Files Verified

- `/Users/sj/Library/Containers/com.mrsane.SaneHosts/Data/Library/Application Support/SaneHosts/Profiles/` - Profile storage
- Profile JSON format is correct and readable
- 3 profiles exist: Default (1 entry), Focus Mode (empty), Test Profile (empty)
