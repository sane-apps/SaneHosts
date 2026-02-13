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

**Sister apps:** SaneBar, SaneClip, SaneVideo, SaneSync, SaneAI, SaneClick

---

## Where to Look First

| Need | Check |
|------|-------|
| Build/test commands | `xcode` MCP (Apple's official via `xcrun mcpbridge`) |
| Project structure | `SaneHosts.xcworkspace` (open this!) |
| Past bugs/learnings | Serena memories (`read_memory`) or official Memory MCP |
| Swift services | `SaneHostsPackage/Sources/SaneHostsFeature/Services/` |
| UI components | `SaneHostsPackage/Sources/SaneHostsFeature/Views/` |
| Models & presets | `SaneHostsPackage/Sources/SaneHostsFeature/Models/` |
| Admin operations | Look for `do shell script` with `administrator privileges` |

---

## PRIME DIRECTIVE (from ~/CLAUDE.md)

> When hooks fire: **READ THE MESSAGE FIRST**. The answer is in the prompt/hook/memory/SOP.
> Stop guessing. Start reading.

---

## Project Overview

SaneHosts is a macOS app for managing `/etc/hosts` file through profiles. It allows users to:
- Choose from 5 **Protection Levels** (Essentials → Kitchen Sink) with curated preset blocklists
- Create and manage host blocking profiles
- Import from 200+ curated blocklists across 10+ categories
- Activate/deactivate profiles with admin authentication
- Flush DNS cache automatically
- First-run **coach mark tutorial** guides new users through activation

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
# Build & Run (xcode MCP)
# Open the workspace in Xcode first

# Open workspace
open /Users/sj/SaneApps/apps/SaneHosts/SaneHosts.xcworkspace

# Run tests in Xcode
# Cmd+U in Xcode, or use xcode MCP RunAllTests
```

---

## MCP Tool Optimization (TOKEN SAVERS)

### xcode MCP (Apple's Official via xcrun mcpbridge)
Requires Xcode running with the workspace open. Get the `tabIdentifier` first:
```
mcp__xcode__XcodeListWindows
mcp__xcode__BuildProject
mcp__xcode__RunAllTests
mcp__xcode__RenderPreview
```
Note: SaneHosts is a **macOS app**. Use `macos-automator` for real UI.

### Serena Memories
Use Serena for project-specific knowledge:
```
read_memory  # Check past learnings
write_memory # Save important findings
```
For cross-project knowledge graph, use official Memory MCP tools.

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
| `ProfileStore` | Profile CRUD, JSON file persistence, activation state management |
| `DNSService` | Flushes DNS cache after hosts file changes |
| `RemoteSyncService` | Imports hosts from remote URLs |
| `HostsParser` | Parses hosts file format |
| `ProfilePresets` | 5-tier protection level definitions with curated blocklist bundles |
| `BlocklistCatalog` | 200+ curated blocklist sources across 10+ categories |

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

### Critical Credentials (SHARED ACROSS ALL SANEAPPS - DO NOT REGENERATE)

| Credential | Value/Location |
|------------|----------------|
| **Sparkle Public Key** | `7Pl/8cwfb2vm4Dm65AByslkMCScLJ9tbGlwGGx81qYU=` |
| **Sparkle Private Key** | macOS Keychain → account `"EdDSA Private Key"` at service `https://sparkle-project.org` |
| **Notarytool Profile** | `notarytool` (in system keychain) |
| **Team ID** | `M78L6FXD48` |

### Release Scripts

```bash
# Build, sign, notarize, create DMG, generate appcast (all-in-one)
./scripts/SaneMaster.rb release

# Test build without notarization
./scripts/SaneMaster.rb release --skip-notarize
```

### Release Steps

```bash
# 1. Build, sign, notarize DMG
./scripts/SaneMaster.rb release

# 2. Upload DMG to Cloudflare R2
npx wrangler r2 object put sanebar-downloads/SaneHosts-X.Y.Z.dmg \
  --file=releases/SaneHosts-X.Y.Z.dmg --content-type="application/octet-stream" --remote

# 3. Update appcast.xml then deploy website
cp docs/appcast.xml website/appcast.xml
CLOUDFLARE_ACCOUNT_ID=2c267ab06352ba2522114c3081a8c5fa \
  npx wrangler pages deploy ./website --project-name=sanehosts-site \
  --commit-dirty=true --commit-message="Release vX.Y.Z"
```

### Notes

- **Cannot sandbox**: Needs to write to `/etc/hosts` (system file)
- **Notarization**: Use hardened runtime + Developer ID signing
- **Entitlements**: No sandbox, but hardened runtime required
