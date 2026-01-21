# SaneHosts Development Guide (SOP)

**Version 1.0** | Last updated: 2026-01-20

> **SINGLE SOURCE OF TRUTH** for all Developers and AI Agents.

---

## Sane Philosophy

```
+-----------------------------------------------------+
|           BEFORE YOU SHIP, ASK:                     |
|                                                     |
|  1. Does this REDUCE fear or create it?             |
|  2. Power: Does user have control?                  |
|  3. Love: Does this help people?                    |
|  4. Sound Mind: Is this clear and calm?             |
|                                                     |
|  Grandma test: Would her life be better?            |
|                                                     |
|  "Not fear, but power, love, sound mind"            |
|  - 2 Timothy 1:7                                    |
+-----------------------------------------------------+
```

> Full philosophy: `~/SaneApps/meta/Brand/NORTH_STAR.md`

---

## THIS HAS BURNED YOU

Real failures from past sessions. Don't repeat them.

| Mistake | What Happened | Prevention |
|---------|---------------|------------|
| **Guessed API** | Assumed API exists. It doesn't. 20 min wasted. | `verify_api` first |
| **Kept guessing** | Same error 4 times. Finally checked apple-docs MCP. | Stop at 2, investigate |
| **Separate ProfileStore instances** | MenuBarProfileStore created separate ProfileStore - state never synced | Use `ProfileStore.shared` singleton |
| **Hardcoded IP filter** | RemoteSyncService rejected valid IPs like 192.168.x.x | Use `HostsParser.isValidIPAddress()` |
| **Serial disk writes** | Bulk operations wrote to disk per entry - severe lag | Use `bulkUpdateEntries()` / `bulkRemoveEntries()` |
| **Missing hardened runtime** | Notarization rejected - missing entitlement | Add `ENABLE_HARDENED_RUNTIME = YES` to Shared.xcconfig |
| **1-second polling for sync** | MenuBarProfileStore polled ProfileStore - wasteful | Use NotificationCenter instead |
| **OISD URLs 404** | OISD discontinued HOSTS format Jan 2024 | URL liveness preflight checks |

**The #1 differentiator**: Skimming this SOP = 5/10 sessions. Internalizing it = 8+/10.

**"If you skim you sin."** - The answers are here. Read them.

---

## Quick Start for AI Agents

**New to this project? Start here:**

1. **Read Rule #0 first** (Section "The Rules") - It's about HOW to use all other rules
2. **All files stay in project** - NEVER write files outside `~/SaneApps/apps/SaneHosts/` unless user explicitly requests it
3. **Use XcodeBuildMCP for builds** - Set session defaults first, never raw `xcodebuild`
4. **Self-rate after every task** - Rate yourself 1-10 on SOP adherence (see Self-Rating section)

### XcodeBuildMCP Session Setup (DO THIS FIRST)

```
mcp__XcodeBuildMCP__session-set-defaults:
  workspacePath: /Users/sj/SaneApps/apps/SaneHosts/SaneHosts.xcworkspace
  scheme: SaneHosts
  arch: arm64
```

Then use `build_macos`, `test_macos`, `build_run_macos` (macOS app, no simulator).

**Key Commands:**
```bash
# Build + Test (via XcodeBuildMCP after setting defaults)
mcp__XcodeBuildMCP__test_macos

# Build + Launch
mcp__XcodeBuildMCP__build_run_macos

# Open workspace
open ~/SaneApps/apps/SaneHosts/SaneHosts.xcworkspace
```

---

## The Rules

### #0: NAME THE RULE BEFORE YOU CODE

DO: State which rules apply before writing code
DON'T: Start coding without thinking about rules

```
RIGHT: "Uses Apple API -> Rule #2: VERIFY BEFORE YOU TRY"
RIGHT: "New file -> Rule #9: NEW FILE? GEN THAT PILE"
WRONG: "Let me just code this real quick..."
```

### #1: STAY IN YOUR LANE

DO: Save all files inside `~/SaneApps/apps/SaneHosts/`
DON'T: Create files outside project without asking

### #2: VERIFY BEFORE YOU TRY

DO: Check API exists before using (apple-docs MCP, context7 MCP)
DON'T: Assume an API exists from memory or web search

**Critical APIs for SaneHosts:**
- `NSAppleScript` - privilege elevation for /etc/hosts writes
- `SMAppService` - if adding privileged helper (future)
- `dscacheutil` - DNS cache flush

### #3: TWO STRIKES? INVESTIGATE

DO: After 2 failures -> stop, follow **Research Protocol** (see section below)
DON'T: Guess a third time without researching

### #4: GREEN MEANS GO

DO: Fix all test failures before claiming done
DON'T: Ship with failing tests

### #5: XCODEBUILDMCP OR DISASTER

DO: Use XcodeBuildMCP tools for all build/test operations
DON'T: Use raw xcodebuild commands

```
# Right
mcp__XcodeBuildMCP__build_macos
mcp__XcodeBuildMCP__test_macos

# Wrong
xcodebuild -workspace SaneHosts.xcworkspace ...
```

### #6: BUILD, KILL, LAUNCH, LOG

DO: Run full sequence after every code change
DON'T: Skip steps or assume it works

```bash
# Kill existing process
killall -9 SaneHosts 2>/dev/null; sleep 1

# Build + launch via XcodeBuildMCP
mcp__XcodeBuildMCP__build_run_macos
```

### #7: NO TEST? NO REST

DO: Every bug fix gets a test that verifies the fix
DON'T: Use placeholder or tautology assertions (`#expect(true)`)

**Test location:** `SaneHostsPackage/Tests/SaneHostsFeatureTests/`

### #8: BUG FOUND? WRITE IT DOWN

DO: Document bugs in TodoWrite immediately
DON'T: Try to remember bugs or skip documentation

### #9: NEW FILE? UPDATE THE PACKAGE

DO: After creating new Swift files, ensure they're in the right SPM target
DON'T: Create files and forget to add them to Package.swift if needed

**Note:** SaneHosts uses SPM package structure (`SaneHostsPackage/`). Files added to existing directories are auto-included. New directories may need Package.swift updates.

### #10: FIVE HUNDRED'S FINE, EIGHT'S THE LINE

| Lines | Status |
|-------|--------|
| <500 | Good |
| 500-800 | OK if single responsibility |
| >800 | Must split |

### #11: TOOL BROKE? FIX THE YOKE

DO: If XcodeBuildMCP fails, debug the issue
DON'T: Work around broken tools

### #12: TALK WHILE I WALK

DO: Use subagents for heavy lifting, stay responsive to user
DON'T: Block on long operations

---

## Self-Rating (MANDATORY)

After each task, rate yourself. Format:

```
**Self-rating: 7/10**
Verified API before using, ran full test cycle
Forgot to run tests after first change
```

| Score | Meaning |
|-------|---------|
| 9-10 | All rules followed |
| 7-8 | Minor miss |
| 5-6 | Notable gaps |
| 1-4 | Multiple violations |

---

## Research Protocol (STANDARD)

This is the standard protocol for investigating problems. Used by Rule #3, Circuit Breaker, and any time you're stuck.

### Tools to Use (ALL of them)

| Tool | Purpose | When to Use |
|------|---------|-------------|
| **Task agents** | Explore codebase, analyze patterns | "Where is X used?", "How does Y work?" |
| **apple-docs MCP** | Verify Apple APIs exist and usage | Any Apple framework API |
| **context7 MCP** | Library documentation | Third-party packages |
| **WebSearch/WebFetch** | Solutions, patterns, best practices | Error messages, architectural questions |
| **Grep/Glob/Read** | Local investigation | Find similar patterns, check implementations |
| **memory MCP** | Past bug patterns, architecture decisions | "Have we seen this before?" |

### Research Output -> Plan

After research, present findings in this format:

```
## Research Findings

### What I Found
- [Tool used]: [What it revealed]
- [Tool used]: [What it revealed]

### Root Cause
[Clear explanation of why the problem occurs]

### Proposed Fix

[Rule #X: NAME] - specific action
[Rule #Y: NAME] - specific action
...

### Verification
- [ ] Tests pass (mcp__XcodeBuildMCP__test_macos)
- [ ] Manual test: [specific check]
```

---

## Circuit Breaker Protocol

The circuit breaker is an automated safety mechanism that **blocks Edit/Bash/Write tools** after repeated failures.

### When It Triggers

| Condition | Threshold | Meaning |
|-----------|-----------|---------|
| **Same error 3x** | 3 identical | Stuck in loop, repeating same mistake |
| **Total failures** | 5 any errors | Flailing, time to step back |

### Recovery Flow

```
CIRCUIT BREAKER TRIPS
         |
         v
+---------------------------------------------+
|  1. READ ERRORS                             |
|     Check what failed and why               |
+---------------------------------------------+
|  2. RESEARCH (use ALL tools above)          |
|     - What API am I misusing?               |
|     - Has this bug pattern happened before? |
|     - What does the documentation say?      |
+---------------------------------------------+
|  3. PRESENT SOP-COMPLIANT PLAN              |
|     - State which rules apply               |
|     - Show what research revealed           |
|     - Propose specific fix steps            |
+---------------------------------------------+
|  4. USER APPROVES PLAN                      |
+---------------------------------------------+
         |
         v
    EXECUTE APPROVED PLAN
```

**Key insight**: Being blocked is not failure - it's the system working. The research phase often reveals the root cause that guessing would never find.

---

## Plan Format (MANDATORY)

Every plan must cite which rule justifies each step. No exceptions.

**Format**: `[Rule #X: NAME] - specific action with file:line or command`

### DISAPPROVED PLAN

```
## Plan: Fix Bug

### Steps
1. Clean build
2. Fix the issue
3. Rebuild and verify

Approve?
```

**Why rejected:**
- No `[Rule #X]` citations - can't verify SOP compliance
- No tests specified (violates Rule #7)
- Vague "fix" without file:line references

### APPROVED PLAN

```
## Plan: Fix [Bug Description]

### Bugs to Fix
| Bug | File:Line | Root Cause |
|-----|-----------|------------|
| [Description] | [File.swift:50] | [Root cause] |

### Steps

[Rule #5: USE XCODEBUILDMCP] - Clean build if needed

[Rule #7: TESTS FOR FIXES] - Create tests:
  - SaneHostsPackage/Tests/SaneHostsFeatureTests/[TestFile].swift

[Rule #6: FULL CYCLE] - Verify fixes:
  - mcp__XcodeBuildMCP__test_macos
  - killall -9 SaneHosts
  - mcp__XcodeBuildMCP__build_run_macos
  - Manual: [specific check]

[Rule #4: GREEN BEFORE DONE] - All tests pass before claiming complete

Approve?
```

---

## Project Structure

```
SaneHosts/
+-- SaneHosts.xcworkspace         # OPEN THIS (workspace with app + SPM)
+-- SaneHosts/                    # App target (minimal entry point)
|   +-- SaneHostsApp.swift
|   +-- Assets.xcassets/
+-- SaneHostsPackage/             # SPM package with all feature code
|   +-- Sources/
|   |   +-- SaneHostsFeature/
|   |       +-- Models/           # Profile, HostEntry
|   |       +-- Services/         # HostsService, ProfileStore, DNSService
|   |       +-- Views/            # SwiftUI views
|   +-- Tests/
|       +-- SaneHostsFeatureTests/
+-- Config/                       # Build configurations
+-- scripts/                      # Release scripts
+-- docs/                         # Documentation
+-- website/                      # Landing page
```

---

## Key Services

| Service | Purpose |
|---------|---------|
| `HostsService` | Reads/writes `/etc/hosts` via AppleScript with admin privileges |
| `ProfileStore` | Profile CRUD and persistence (UserDefaults + JSON files) |
| `DNSService` | Flushes DNS cache after hosts file changes |
| `RemoteSyncService` | Imports hosts from remote URLs (blocklists) |
| `HostsParser` | Parses hosts file format |

**Singleton Pattern:** Use `ProfileStore.shared` for app-wide state sharing.

---

## Security Considerations

| Aspect | Details |
|--------|---------|
| **Admin Authentication** | Hosts file modifications require admin password |
| **AppleScript Elevation** | Uses `do shell script with administrator privileges` |
| **No Sandbox** | Required to write `/etc/hosts` (system file) |
| **Hardened Runtime** | Required for notarization |
| **Entitlements** | `com.apple.security.automation.apple-events` for AppleScript |

---

## Data Locations

| Data | Location |
|------|----------|
| **Profiles** | `~/Library/Application Support/SaneHosts/Profiles/*.json` |
| **UserDefaults** | Standard UserDefaults for settings |
| **Derived Data** | `~/Library/Developer/Xcode/DerivedData/SaneHosts-*/` |

---

## MCP Tool Optimization (TOKEN SAVERS)

### XcodeBuildMCP (Required)
Set defaults ONCE at session start:
```
mcp__XcodeBuildMCP__session-set-defaults:
  workspacePath: /Users/sj/SaneApps/apps/SaneHosts/SaneHosts.xcworkspace
  scheme: SaneHosts
  arch: arm64
```

### claude-mem 3-Layer Workflow (10x Token Savings)
```
1. search(query, project: "SaneHosts") -> Get index with IDs
2. timeline(anchor=ID)                  -> Get context around results
3. get_observations([IDs])              -> Fetch ONLY filtered IDs
```
**Always add `project: "SaneHosts"` to searches for isolation.**

### apple-docs Optimization
- `compact: true` works on `list_technologies`, `get_sample_code`, `wwdc` (NOT on `search_apple_docs`)
- `analyze_api analysis="all"` for comprehensive API analysis

### context7 for Library Docs
- `resolve-library-id` FIRST, then `query-docs`
- SwiftUI ID: `/websites/developer_apple_swiftui` (13,515 snippets!)

---

## Distribution

**See `docs/DISTRIBUTION.md` for full release checklist.**

### Critical Credentials (DO NOT REGENERATE)

| Credential | Value/Location |
|------------|----------------|
| **Sparkle Public Key** | `QwXgCpqQfcdZJ6BIzLRrBmn2D7cwkNbaniuIkm/DJyQ=` |
| **Sparkle Private Key** | macOS Keychain (account: ed25519) |
| **Notarytool Profile** | `notarytool` (in system keychain) |
| **Team ID** | `M78L6FXD48` |

### Release Scripts

```bash
# Build, sign, notarize, create DMG
./scripts/build_release.sh

# Generate Sparkle appcast.xml
./scripts/generate_appcast.sh
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Ghost beeps / no launch | Ensure workspace is open, rebuild |
| Phantom build errors | Clean via XcodeBuildMCP, delete DerivedData |
| "File not found" after new file | Check SPM package includes the file |
| Tests failing mysteriously | Clean build, check for stale derived data |
| Password prompt not appearing | Check `NSAppleScript` entitlements |
| DNS not flushing | Check `dscacheutil -flushcache` works manually |
| State not syncing | Use `ProfileStore.shared` singleton |
| Notarization fails | Check hardened runtime is enabled |
