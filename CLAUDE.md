# SaneHosts Project Configuration

> Project-specific settings that override/extend the global ~/CLAUDE.md

---

## Sane Philosophy

```
┌─────────────────────────────────────────────────────┐
│           BEFORE YOU SHIP, ASK:                     │
│                                                     │
│  1. Does this REDUCE fear or create it?             │
│  2. Power: Does user have control?                  │
│  3. Love: Does this help people?                    │
│  4. Sound Mind: Is this clear and calm?             │
│                                                     │
│  Grandma test: Would her life be better?            │
│                                                     │
│  "Not fear, but power, love, sound mind"            │
│  — 2 Timothy 1:7                                    │
└─────────────────────────────────────────────────────┘
```

→ Full philosophy: `~/SaneApps/meta/Brand/NORTH_STAR.md`

---

## Project Location

| Path | Description |
|------|-------------|
| **This project** | `~/SaneApps/apps/SaneHosts/` |
| **Save outputs** | `~/SaneApps/apps/SaneHosts/outputs/` |
| **Screenshots** | `~/Desktop/Screenshots/` (label with project prefix) |
| **Shared UI** | `~/SaneApps/infra/SaneUI/` |
| **Hooks/tooling** | `~/SaneApps/infra/SaneProcess/` |

**Sister apps:** SaneBar, SaneClip, SaneVideo, SaneSync, SaneAI, SaneScript

---

## Where to Look First

| Need | Check |
|------|-------|
| Build/test commands | `scripts/SaneMaster.rb --help` or XcodeBuildMCP |
| Project structure | `SaneHosts.xcworkspace` (open this!) |
| Past bugs/learnings | `.claude/memory.json` or MCP memory |
| Swift services | `SaneHostsFeatures/Sources/` |
| UI components | `SaneHosts/Views/` directory |
| Admin operations | Look for `do shell script` with `administrator privileges` |

---

## PRIME DIRECTIVE (from ~/CLAUDE.md)

> When hooks fire: **READ THE MESSAGE FIRST**. The answer is in the prompt/hook/memory/SOP.
> Stop guessing. Start reading.

---

## Project Overview

SaneHosts is a macOS app for managing `/etc/hosts` file through profiles. It allows users to:
- Create and manage host blocking profiles
- Import hosts from remote URLs (ad blocking lists, etc.)
- Activate/deactivate profiles with admin authentication
- Flush DNS cache automatically

**Key Architecture Note**: The app modifies `/etc/hosts` using AppleScript with administrator privileges (`do shell script with administrator privileges`). This triggers a system password prompt for the user.

---

## Project Structure

| Path | Purpose |
|------|---------|
| `SaneHosts.xcworkspace` | **Open this** - workspace with app + SPM package |
| `SaneHosts/` | App target (minimal - just entry point) |
| `SaneHostsPackage/` | SPM package with all feature code |
| `SaneHostsPackage/Sources/SaneHostsFeature/` | Main feature code |
| `SaneHostsPackage/Sources/SaneHostsFeature/Models/` | Data models (Profile, HostEntry) |
| `SaneHostsPackage/Sources/SaneHostsFeature/Services/` | Business logic services |
| `SaneHostsPackage/Sources/SaneHostsFeature/Views/` | SwiftUI views |
| `SaneHostsPackage/Tests/` | Unit tests |
| `Config/` | Build configurations |
| `docs/` | Documentation |

---

## Quick Commands

```bash
# Build & Run (use XcodeBuildMCP)
# First set session defaults, then use build_run_macos

# Open workspace
open /Users/sj/SaneApps/apps/SaneHosts/SaneHosts.xcworkspace

# Run tests in Xcode
# Cmd+U in Xcode, or use XcodeBuildMCP test_macos
```

---

## MCP Tool Optimization (TOKEN SAVERS)

### XcodeBuildMCP Session Setup
At session start, set defaults ONCE to avoid repeating on every build:
```
mcp__XcodeBuildMCP__session-set-defaults:
  workspacePath: /Users/sj/SaneApps/apps/SaneHosts/SaneHosts.xcworkspace
  scheme: SaneHosts
  arch: arm64
```
Note: SaneHosts is a **macOS app** - no simulator needed. Use `build_macos`, `test_macos`, `build_run_macos`.

### claude-mem 3-Layer Workflow (10x Token Savings)
```
1. search(query, project: "SaneHosts") → Get index with IDs (~50-100 tokens/result)
2. timeline(anchor=ID)                 → Get context around results
3. get_observations([IDs])             → Fetch ONLY filtered IDs
```
**Always add `project: "SaneHosts"` to searches for isolation.**

### apple-docs Optimization
- `compact: true` works on `list_technologies`, `get_sample_code`, `wwdc` (NOT on `search_apple_docs`)
- `analyze_api analysis="all"` for comprehensive API analysis
- `apple_docs` as universal entry point (auto-routes queries)

### context7 for Library Docs
- `resolve-library-id` FIRST, then `query-docs`
- SwiftUI ID: `/websites/developer_apple_swiftui` (13,515 snippets!)

### github MCP
- `search_code` to find patterns in public repos
- `search_repositories` to find reference implementations

---

## Key Services

| Service | Purpose |
|---------|---------|
| `HostsService` | Reads/writes `/etc/hosts` via AppleScript with admin privileges |
| `ProfileStore` | Profile CRUD and persistence (UserDefaults) |
| `DNSService` | Flushes DNS cache after hosts file changes |
| `RemoteSyncService` | Imports hosts from remote URLs |
| `HostsParser` | Parses hosts file format |

---

## Security Considerations

- **Admin Authentication**: Hosts file modifications require admin password
- **AppleScript Elevation**: Uses `do shell script with administrator privileges`
- **No Privileged Helper**: Uses AppleScript instead of XPC/SMAppService for simplicity
- **Future**: May migrate to privileged helper (XPC, SMAppService) for better UX

---

## Key APIs to Verify Before Using

```bash
# Always verify these exist before coding:
# - NSAppleScript for privilege elevation
# - SMAppService (if adding privileged helper)
# - dscacheutil (DNS flush)
```

---

## Testing

### Unit Tests
Tests are in `SaneHostsPackage/Tests/SaneHostsFeatureTests/`:
- Model tests (Profile, HostEntry)
- Parser tests (HostsParser)
- Service tests (mocked)

### Manual Testing
See `SESSION_HANDOFF.md` for comprehensive UI test plan.

---

## Known Limitations

1. **AppleScript auth** - Password prompt for each activation (XPC would remember)
2. **No sandbox** - Required to write `/etc/hosts`

---

## Claude Code Features (USE THESE!)

### Key Commands

| Command | When to Use | Shortcut |
|---------|-------------|----------|
| `/rewind` | Rollback code AND conversation after errors | `Esc+Esc` |
| `/context` | Visualize context window token usage | - |
| `/compact [instructions]` | Optimize memory with focus | - |
| `/stats` | See usage patterns (press `r` for date range) | - |

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Esc+Esc` | Rewind to checkpoint |
| `Shift+Tab` | Cycle permission modes (Normal → Auto-Accept → Plan) |
| `Option+T` | Toggle extended thinking |
| `Ctrl+O` | Toggle verbose mode |
| `Ctrl+B` | Background running task |

### Smart /compact Instructions

Don't just run `/compact` - give it focus instructions:
```
/compact keep SaneHosts hosts file management patterns and service architecture, archive general Swift tips
```

### Use Explore Subagent for Searches

For large codebase searches, delegate to Explore (Haiku-powered, saves context):
```
Task tool with subagent_type: Explore
```

---

## Distribution (READY)

**See `docs/DISTRIBUTION.md` for full release checklist.**

### Critical Credentials (ALREADY EXIST - DO NOT REGENERATE)

| Credential | Value/Location |
|------------|----------------|
| **Sparkle Public Key** | `QwXgCpqQfcdZJ6BIzLRrBmn2D7cwkNbaniuIkm/DJyQ=` |
| **Sparkle Private Key** | macOS Keychain → "Private key for signing Sparkle updates" |
| **Notarytool Profile** | `notarytool` (in system keychain) |
| **Team ID** | `M78L6FXD48` |

### Release Scripts

```bash
# Build, sign, notarize, create DMG
./scripts/build_release.sh

# Generate Sparkle appcast.xml
./scripts/generate_appcast.sh
```

### Remaining Steps for v1.0

- [ ] Purchase domain (sanehosts.com)
- [ ] Create GitHub repo (github.com/sane-apps/SaneHosts)
- [ ] Run `./scripts/build_release.sh`
- [ ] Create GitHub release with DMG
- [ ] Deploy website + appcast.xml

### Notes

- **Cannot sandbox**: Needs to write to `/etc/hosts` (system file)
- **Notarization**: Use hardened runtime + Developer ID signing
- **Entitlements**: No sandbox, but hardened runtime required
