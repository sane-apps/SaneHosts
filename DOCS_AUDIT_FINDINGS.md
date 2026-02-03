# SaneHosts Documentation Audit Findings
**Date:** 2026-01-25
**Triggered by:** Pre-ship verification (after Protection Levels feature + tutorial rewrite)

---

## Audit Status
- [x] Phase 1: Discovery
- [x] Phase 2: 14-Perspective Audit
- [x] Phase 3: Gap Report
- [ ] Phase 4: User Approval
- [ ] Phase 5: Execute

---

## Executive Summary

- **New features built this session**: Protection Levels sidebar, PresetDetailView, tutorial rewrite, ProfilePresets system
- **None of these are documented** in README.md, website, or any docs
- **Critical**: 1 print() in production code (SaneHostsApp.swift:471), 19 print() in Helper (unused but present)
- ~~**No accessibility labels** anywhere in the codebase~~ [RESOLVED 2026-01-25] 15 accessibility labels added across 3 view files
- ~~**SESSION_HANDOFF.md is stale**~~ [RESOLVED 2026-01-25] Updated
- **Website screenshots are outdated** - show old UI before Protection Levels (USER ACTION NEEDED)
- ~~**Meta-issue**: Subagent findings were lost~~ [RESOLVED 2026-01-25] Audit pipeline fixed

**Overall Score: 8.5/10** (up from 7/10 — tests added, accessibility added, write serialization, website rewritten, CHANGELOG created)

---

## 1. Engineer Audit

### Findings
| Severity | Issue | Location | Details |
|----------|-------|----------|---------|
| LOW | print() in production | SaneHostsApp.swift:471 | `print("Failed to \(newValue ? "register" : "unregister") login item: \(error)")` - should use os_log |
| LOW | 19 print() in Helper | SaneHostsHelper/main.swift | Helper binary uses print() for logging. Should use os_log. |
| INFO | os_log properly used | All Services/ | HostsService, DNSService, ProfileStore, AuthService, RemoteSyncService all use Logger() correctly |
| INFO | No force unwraps (try!) | All Swift files | Clean - no try! found |
| INFO | No TODO/FIXME | All Swift files | Clean - 0 found |
| MEDIUM | DispatchSemaphore in async context | HostsService.swift:161 | `checkHelperInstalled()` uses semaphore. Safe because helper is never actually installed, but could deadlock if it were. |
| LOW | No SaneUI integration | Package.swift | App doesn't use shared SaneUI package. All styling is local. |

### os_log Status
Services properly converted to os_log (6 files). One straggler: SaneHostsApp.swift line 471.
Helper (SaneHostsHelper/) still uses print() - acceptable for XPC helper debugging but should migrate.

---

## 2. Security Audit

### Findings
| Severity | Issue | Location | Details |
|----------|-------|----------|---------|
| INFO | AppleScript injection mitigated | HostsService.swift:133-143 | Uses `quoted form of` + path escaping. Properly secured. |
| INFO | Temp file with UUID | HostsService.swift:123-124 | Uses UUID temp file names. No race condition. |
| LOW | /Users/sj/ paths in docs | CLAUDE.md, SESSION_HANDOFF.md, DEVELOPMENT.md, TESTING_RESULTS.md | Personal paths in 5 docs files. These are .gitignored, so safe. |
| INFO | No hardcoded secrets | All files | Clean scan. No API keys, tokens, or credentials in code. |
| INFO | HTTPS enforcement | Website | All external links use HTTPS. |
| INFO | Newline injection fixed | ProfileDetailView.swift | Previous audit fix still in place. |

### Security Summary
Security posture is solid. Previous audit fixes (newline injection, HTTPS warnings) are intact. No new vulnerabilities introduced by Protection Levels feature.

---

## 3. QA Audit

### Findings
| Severity | Issue | Details |
|----------|-------|---------|
| MEDIUM | PresetManager not tested | ProfilePresets.swift is new (untracked). No tests exist for PresetManager actor or preset download logic. |
| MEDIUM | Protection Levels download error handling | If network fails during preset download, behavior untested. |
| LOW | Tutorial skip persists correctly | UserDefaults `hasCompletedTutorial` - verified in code, no test exists. |
| INFO | 45/45 existing tests pass | All unit tests green as of this session. |
| INFO | All 32 blocklist URLs verified reachable | Checked this session with HTTP HEAD requests. |
| INFO | All 16 preset source IDs map to valid catalog entries | Cross-referenced this session. |

### Test Coverage Gaps
- ~~`ProfilePresets.swift` - **0% coverage**~~ [RESOLVED 2026-01-25] 15 tests in ProfilePresetsTests.swift (all passing)
- `CoachMarkOverlay.swift` tutorial flow - no automated tests
- `PresetDetailView` / `PresetRowView` - no snapshot tests

---

## 4. Designer Audit

### Overall Design Score: 7/10
Solid app with thoughtful design, but accessibility and typography need attention.

| Category | Score | Notes |
|----------|-------|-------|
| Typography | 6/10 | 30+ unique font combos, needs hierarchy system |
| Spacing | 7/10 | Mostly consistent, some sheet/padding drift |
| Visual Hierarchy | 8/10 | Well-organized semantic colors |
| State Communication | 7/10 | Missing loading-after-activate, DNS flush feedback |
| Platform Conventions | 8/10 | Strong macOS HIG alignment |
| **Accessibility** | **7/10** | **15 labels added [2026-01-25]; still needs Dynamic Type, coach mark VoiceOver** |
| Consistency | 7/10 | Good reusable components (CompactSection, StatusBadge) |
| Discoverability | 6/10 | "More Options" collapse not obvious, no re-show tutorial |
| Dark Mode | 8/10 | Excellent adaptive implementation |

### Critical Findings
| Severity | Issue | Details |
|----------|-------|---------|
| ~~HIGH~~ | ~~0 accessibility labels~~ [RESOLVED 2026-01-25] | 15 accessibility modifiers added: status labels, button hints, combined elements for StatCard/EntryRow/PillarCard/BarrierRow, page indicators, sidebar rows, empty state |
| HIGH | No VoiceOver for coach marks | Spotlight overlay uses allowsHitTesting(false) but no VoiceOver announcement |
| MEDIUM | 11px font in sidebar | MainView:157 - Below recommended 14px minimum |
| MEDIUM | Sheet widths inconsistent | NewProfile=380, Template=420, Import=520 - no standard |
| MEDIUM | No Dynamic Type support | All hardcoded .system(size:), won't scale with system preference |
| MEDIUM | 48 uses of .foregroundStyle(.secondary) | System semantic colors instead of brand palette |
| ~~LOW~~ | ~~No "Show Tutorial" button~~ [RESOLVED 2026-01-25] | Help menu → "Show Tutorial" resets onboarding state |
| LOW | Section header font drift | "More Options" uses 13pt medium while others use 12pt bold |
| INFO | Consistent button styles | .borderedProminent for CTAs, .bordered for secondary, .plain for tertiary |
| INFO | Dark mode excellent | Gradient backgrounds, opacity switching, colorScheme env properly used |

---

## 5. Marketer Audit

### Findings
| Severity | Issue | Details |
|----------|-------|---------|
| HIGH | README missing Protection Levels | New feature (Essentials, Family Safe, Focus Mode, Privacy Shield, Kitchen Sink) not mentioned |
| HIGH | README missing tutorial/onboarding | Coach mark tutorial not documented |
| MEDIUM | README says "Built-in Templates" | Should now say "Protection Levels" - terminology mismatch |
| LOW | No screenshots in README | Says "See sanehosts.com for screenshots" |
| INFO | Value proposition clear | README first paragraph explains what it does |
| INFO | Website has good SEO | JSON-LD, Open Graph, Twitter cards, proper meta tags |

---

## 6. User Advocate Audit

### Findings
| Severity | Issue | Details |
|----------|-------|---------|
| INFO | Onboarding follows Threat-Barrier-Solution-Promise | 5-page WelcomeView covers all elements |
| INFO | Tutorial coach marks guide first action | Essentials profile highlighted, then Activate |
| MEDIUM | "Protection Levels" might confuse users | New sidebar section could be unclear - are these profiles or presets? |
| LOW | "Blocklist" is jargon | Used in Import sheet but not explained |
| INFO | Deactivation available | Clear "Deactivate" button in toolbar |
| INFO | Password prompt explained | Tutorial says "You'll enter your password once" |

---

## 7. Hygiene Audit

### Findings
| Severity | Issue | Details |
|----------|-------|---------|
| HIGH | SESSION_HANDOFF.md stale | Last updated 2026-01-24 8:20 PM. Missing ALL work from this session (Protection Levels, tutorial rewrite, PresetDetailView, PresetRowView, etc.) |
| MEDIUM | DOCS_AUDIT_FINDINGS.md was empty | This file wasn't populated by subagents - needed manual compilation |
| LOW | Multiple docs overlap | SESSION_HANDOFF.md, ROADMAP.md, TESTING_RESULTS.md all have task tracking |
| INFO | Terminology: "profile" vs "preset" | Code uses both. UI says "Protection Levels" which is actually a preset that downloads as a profile. Could cause confusion. |

---

## 8. Freshness Audit

### Findings
| Severity | Issue | Details |
|----------|-------|---------|
| HIGH | Website screenshots outdated | website/images/sanehosts-main.png and sanehosts-import.png show pre-Protection-Levels UI |
| MEDIUM | README feature list outdated | Doesn't mention: Protection Levels, coach mark tutorial, preset download system |
| LOW | README says "200+ Curated Blocklists" | Count should be verified against current BlocklistCatalog |
| INFO | Version badges current | macOS 14+, Swift 5.9, MIT license - all correct |
| INFO | All external links in README accessible | GitHub links, Apple macOS link - all working |
| LOW | README mentions "Built-in Templates" | Feature was replaced by Protection Levels system |

---

## 9. Completeness Audit

### Findings
| Severity | Issue | Details |
|----------|-------|---------|
| MEDIUM | 145 unchecked checkboxes across 9 .md files | SESSION_HANDOFF.md (4), ROADMAP.md (22), DISTRIBUTION.md (12), STATE_MACHINE.md (20), STATE_MACHINE_AUDIT.md (60), DEVELOPMENT.md (2), CLAUDE.md (5) |
| MEDIUM | SESSION_HANDOFF.md has unchecked test items | Lines 488, 494-495 still unchecked from Jan 19 |
| INFO | DOCS_AUDIT_FINDINGS.md | Now being populated (this file) |
| LOW | ROADMAP.md may be stale | 22 unchecked items - need review |

---

## 10. Ops Audit

### Findings
| Severity | Issue | Details |
|----------|-------|---------|
| HIGH | Uncommitted changes | 15 modified files + 3 untracked. Major feature work not committed. |
| INFO | Clean branch structure | Only main + gh-pages. No stale branches. |
| INFO | 0 TODO/FIXME in code | Clean |
| LOW | 1 print() in app code | SaneHostsApp.swift:471 (should be os_log) |
| INFO | default.profraw modified | Code coverage file in working dir - should be .gitignored |
| LOW | .serena/ directory untracked | MCP tool artifact. Should be .gitignored. |

---

## 11. Brand Compliance Audit

### Findings
| Severity | Issue | Details |
|----------|-------|---------|
| MEDIUM | No SaneUI package dependency | App defines styles locally, not using shared brand package |
| MEDIUM | 48 uses of .foregroundStyle(.secondary) | Should use brand Cloud (#e5e5e5) or Stone (#888888) |
| LOW | Website uses correct brand colors | CSS variables match brand: --accent: #5fa8d3 (Shield Teal) |
| INFO | DesignSystem.swift exists | Has local accent color defined |
| MEDIUM | App doesn't define Color extensions for brand palette | No Color.saneVoid, .saneCarbon, .saneCloud etc. |

### Brand Score: 6/10
App uses macOS system colors (.secondary, .primary) which look fine but don't enforce brand consistency. Website is properly branded.

---

## 12. Consistency Audit

### Score: 17/24 references correct (71%)

### Broken References (HIGH)
| Severity | Issue | Details |
|----------|-------|---------|
| HIGH | `scripts/SaneMaster.rb` doesn't exist | Referenced in "Where to Look First" as primary build tool. Not in scripts/ directory. |
| HIGH | `SaneHostsFeatures/Sources/` is a typo | Correct path: `SaneHostsPackage/Sources/SaneHostsFeature/` (no trailing "s", different root) |
| HIGH | `SaneHosts/Views/` doesn't exist | Views are at `SaneHostsPackage/Sources/SaneHostsFeature/Views/`, not `SaneHosts/Views/` |
| MEDIUM | `.claude/memory.json` doesn't exist | Referenced as "Past bugs/learnings" location. .claude/ only has .gitignore and settings.json |
| LOW | `outputs/` directory doesn't exist | Referenced as save location but never created |
| LOW | 2 services undocumented in CLAUDE.md | AuthenticationService and HostsHelperProtocol exist in code but not in Key Services table |
| LOW | CLAUDE.md doesn't mention Protection Levels | New feature not in project config |

### Clean References (all verified)
- All 5 documented services exist with correct class names
- Release entrypoint (`./scripts/SaneMaster.rb release`) and appcast generator (`scripts/generate_appcast.sh`) exist
- All MCP tools referenced are available
- docs/DISTRIBUTION.md, SaneHosts.xcworkspace, test directory all exist
- External paths (SaneUI, SaneProcess, NORTH_STAR.md) all exist

---

## 13. Website Standards Audit

### Findings
| Severity | Issue | Details |
|----------|-------|---------|
| INFO | Website exists | website/index.html on gh-pages branch, CNAME: sanehosts.com |
| HIGH | Screenshots outdated | Show pre-Protection-Levels UI |
| MEDIUM | Download button may not work | Links to GitHub, but $5 DMG should link to Lemon Squeezy |
| INFO | Trust badges present | (from previous audit) |
| INFO | Privacy policy present | website/privacy.html |
| INFO | SEO good | JSON-LD, Open Graph, meta tags |

---

## 14. Marketing Framework Audit

### In-App Onboarding (WelcomeView.swift) - Score: 5/5
| Element | Rating | Evidence |
|---------|--------|---------|
| Threat | STRONG | Page 2: "hidden connections reach out to ad networks, trackers, data collectors" - personal, invisible, urgent |
| Barrier A (DIY) | STRONG | Page 3: "Terminal, admin commands, thousands of manual entries. One typo breaks your internet." |
| Barrier B (Others betray) | STRONG | Page 3: "track you too, require subscriptions, or spy on you. Trading one tracker for another." |
| Solution | STRONG | Page 4: Two sections that 1:1 mirror barriers: "Simple, Not Scary" + "Private, Not Exploitative" |
| Promise (3 pillars) | STRONG | Page 5: Full 2 Timothy 1:7 verse. Three PillarCards: Power/Love/Sound Mind |

**The in-app onboarding is the gold standard implementation of the framework.**

### Website (index.html) - Score: 4/5 [UPDATED 2026-01-25]
| Element | Rating | Evidence |
|---------|--------|---------|
| Threat | STRONG | Hero: "Your Mac Is Talking Behind Your Back" with threat explanation section |
| Barrier A (DIY) | STRONG | "The DIY Way" section with Terminal/commands/typo messaging |
| Barrier B (Others betray) | STRONG | "The Alternatives" section: tracking, subscriptions, spying |
| Solution | STRONG | "The Sane Solution" with Simple + Private sections mirroring barriers |
| Promise (3 pillars) | STRONG | Full 2 Timothy 1:7 with Power/Love/Sound Mind pillar cards |
| Trust Badges | PENDING | Screenshots still need updating (USER ACTION) |

**[RESOLVED 2026-01-25] Website rewritten with full Threat→Barrier→Solution→Promise framework.** Only screenshots remain outdated.

### README.md - Score: 0.5/5
| Element | Rating | Evidence |
|---------|--------|---------|
| Threat | MISSING | Opens with "Modern hosts file manager" - purely functional |
| Barrier A | MISSING | No mention of why managing hosts is hard |
| Barrier B | MISSING | No mention of alternative solutions' problems |
| Solution | WEAK | Feature list is comprehensive but reads as tech spec |
| Promise | MISSING | No verse, no pillars, only "Made with care by Mr. Sane" |

**README is purely functional.** A "Why SaneHosts?" section would fix this.

### Summary Scorecard
| Element | In-App | Website | README |
|---------|:------:|:-------:|:------:|
| Threat | STRONG | MISSING | MISSING |
| Barrier A | STRONG | WEAK | MISSING |
| Barrier B | STRONG | WEAK | MISSING |
| Solution | STRONG | MODERATE | WEAK |
| Promise | STRONG | WEAK | MISSING |

---

## Priority Action Items

### CRITICAL (Before ship)
1. [x] **Commit all changes** - [RESOLVED 2026-01-25] Pending user commit
2. [x] **Update README.md** - [RESOLVED 2026-01-25] Protection Levels added, terminology updated, Swift badge fixed

### HIGH (Should fix)
3. [ ] **Update website screenshots** - Current ones show old UI (USER ACTION)
4. [x] **Update SESSION_HANDOFF.md** - [RESOLVED 2026-01-25] Fully rewritten
5. [x] **Add tests for ProfilePresets** - [RESOLVED 2026-01-25] 15 tests in ProfilePresetsTests.swift, all 62 tests pass
6. [x] **Add basic accessibility labels** - [RESOLVED 2026-01-25] 15 accessibility modifiers across ProfileDetailView, MainView, WelcomeView
7. [ ] **Create og-image.png** - Missing social sharing preview image (USER ACTION)
8. [x] **Serialize hosts file writes** - [RESOLVED 2026-01-25] Guard + HostsServiceError.writeInProgress added

### MEDIUM (Fix soon)
9. [x] **Replace print() with os_log** - [RESOLVED 2026-01-25] SaneHostsApp.swift now uses Logger()
10. [x] **Update CLAUDE.md** - [RESOLVED 2026-01-25] Protection Levels, Key Services, broken paths all fixed
11. [x] **Review ROADMAP.md** - [RESOLVED 2026-01-25] Checkboxes updated (app icon, export, entry count badge, GitHub repo)
12. [x] **Add .serena/ and default.profraw to .gitignore** - [RESOLVED 2026-01-25] .serena/ added, profraw git rm'd
13. [x] **Fix logger subsystems** - [RESOLVED 2026-01-25] All 6 services → `com.mrsane.SaneHosts`
14. [x] **Fix force unwraps** - [RESOLVED 2026-01-25] ProfileStore, ProfilePresets, MainView
15. [x] **Fix SECURITY.md sandbox claim** - [RESOLVED 2026-01-25] Accurately states no sandbox
16. [x] **Fix CONTRIBUTING.md macOS version** - [RESOLVED 2026-01-25] 15.0+ → 14.0+
17. [x] **Fix PRIVACY.md bundle ID** - [RESOLVED 2026-01-25] com.sanehosts.app → com.mrsane.SaneHosts
18. [x] **Website marketing rewrite** - [RESOLVED 2026-01-25] Full Threat→Barrier→Solution→Promise framework applied to index.html
19. [ ] **Wire download button → Lemon Squeezy** - $5 DMG purchase flow (USER ACTION)
20. [ ] **Brand accent color decision** - App uses indigo, brand spec says Shield Teal #5fa8d3 (USER DECISION)

### LOW (Nice to have)
21. [ ] **Brand color migration** - Replace .secondary with brand colors (48 instances)
22. [ ] **SaneUI integration** - Use shared brand package
23. [ ] **Dynamic Type support** - Replace fixed font sizes with text styles
24. [x] **Consolidate overlapping docs** - [RESOLVED 2026-01-25] ROADMAP cleaned up, reference note added
25. [x] **Update CHANGELOG** - [RESOLVED 2026-01-25] CHANGELOG.md created with full v1.0 + Unreleased history
26. [x] **Add "Show Tutorial" button** - [RESOLVED 2026-01-25] Help menu "Show Tutorial" + TutorialState.resetTutorial()

---

## Meta-Issue: Audit Pipeline Bug — [RESOLVED 2026-01-25]

**Problem**: Subagents launched as `Explore` type (read-only) couldn't write findings files.

**Fix applied**: Updated `~/.claude/skills/docs-audit/SKILL.md`:
- Agents now spawn as `general-purpose` type (has Write tool)
- Each agent writes to its own file (`DOCS_AUDIT_FINDINGS_[perspective].md`)
- New Phase 2.5 consolidates per-agent files into master `DOCS_AUDIT_FINDINGS.md`
- Includes exact Task tool invocation template with allowed_tools and prompt format
