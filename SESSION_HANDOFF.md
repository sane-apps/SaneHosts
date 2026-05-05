# Session Handoff — SaneHosts

**Last updated:** 2026-05-05

## Current State

- Current direct-download release is `1.1.9` (build `1109`).
- SaneHosts remains direct-download only. The App Store lane is intentionally disabled for the current helper/daemon architecture.
- Pricing rollout source of truth for current customer-facing surfaces: `Basic = free`, `Pro = $14.99 once`, `direct download only`.
- Do not reintroduce App Store positioning in customer-facing copy unless the product is intentionally redesigned around an App-Store-safe architecture.
- Track pricing impact with `ruby ~/SaneApps/infra/SaneProcess/scripts/SaneMaster.rb sales --products`, `downloads --app SaneHosts --days 30`, and `events --app SaneHosts --days 30` before and after rollout windows.
- Use `CHANGELOG.md` for current release history. The notes below are archival context.

## Completed May 5, 2026

- Shipped direct-download `v1.1.9` after reviewing the external `pluja/awesome-privacy#668` / `Lissy93/awesome-privacy#411` security and privacy feedback.
- Hardening included: library validation enabled, helper-side hosts-content validation, generated hosts comment/profile-name sanitization, remote import and built-in blocklist size caps, private profile/cache permissions, stricter edit-entry hostname validation, safer direct-distribution AppleScript paths, and updated privacy/security disclosures.
- UI/copy cleanup included: Basic/Pro quick actions no longer truncate, Pro gating is visually clear, all SaneHosts app text foreground paths avoid gray/low-opacity text, website body text tokens were moved to white/off-white, and public copy now describes the direct-download privacy model without scare wording.
- Verification on the Mac Mini:
  - `swift test --package-path SaneHostsPackage` passed: 77 Swift Testing tests plus 2 XCTest integration tests.
  - `./scripts/SaneMaster.rb verify` passed repeatedly, including the pre-push hook and release script: 81 total tests.
  - Focused Mini-side Xcode build of `SaneHosts` passed and compiled `SaneHostsHelper`.
  - Mini runtime launch passed in both Basic and Pro modes using `sane_test.rb`; screenshots inspected at `/tmp/sanehosts-mini-basic-white-20260505.png` and `/tmp/sanehosts-mini-pro-white-20260505.png`.
  - Mini Safari website checks inspected home and privacy pages at `/tmp/sanehosts-mini-safari-home-white2-20260505.png` and `/tmp/sanehosts-mini-safari-privacy-white-20260505.png`.
  - Upgrade-path probe confirmed existing profiles still present, profile/backups directories at `700`, and profile JSON files at `600`.
  - Direct release script completed: notarization accepted, ZIP uploaded, appcast deployed, Cloudflare Pages deployed, Homebrew cask updated, email webhook updated, and strict post-release checks passed.
- Follow-up still needed: get user approval for exact public GitHub reply drafts before posting to `pluja/awesome-privacy#668` and optionally the closed `Lissy93/awesome-privacy#411`.

## Archived Notes

## Current Product Strategy

- SaneHosts is now **direct-download only**.
- The macOS App Store lane is intentionally disabled in [`.saneprocess`](.saneprocess).
- Reason: the current SaneHosts architecture depends on a privileged helper / `SMAppService.daemon` / `launchd` flow to modify `/etc/hosts`, which is not Mac-App-Store-safe.
- Do not spend more App Review cycles on the current architecture unless the product is redesigned around an App-Store-safe model.

## ✅ COMPLETED: Xcode 26.3 MCP Migration (Feb 13)

Apple released **Xcode 26.3 RC** with `xcrun mcpbridge` — official MCP replacing community XcodeBuildMCP.

**Migration complete:**
- ✅ Global config: `~/.claude.json` has `xcode` server, `~/.claude/settings.json` has `mcp__xcode__*` permission
- ✅ `CLAUDE.md` — All XcodeBuildMCP references replaced with `xcode` MCP
- ✅ `.mcp.json` — No XcodeBuildMCP entry (was already clean)
- ✅ Project uses official `xcode` MCP via `xcrun mcpbridge`

**xcode quick ref:** 20 tools via `xcrun mcpbridge`. Needs Xcode running + project open. All tools need `tabIdentifier` (get from `XcodeListWindows`). Key tools: `BuildProject`, `RunAllTests`, `RunSomeTests`, `RenderPreview`, `DocumentationSearch`, `GetBuildLog`.

---

## Completed Last Session (Jan 31)

### Cross-Site Unification (all 4 SaneApps websites)
- **SEO meta tags unified**: Added missing author, robots, theme-color, apple-touch-icon, apple-mobile-web-app-title, og:site_name, og:locale, twitter:site, twitter:url across SaneHosts, SaneBar, SaneClick (SaneClip was already complete)
- **JSON-LD enriched**: Added featureList, softwareVersion, author, Organization schema to SaneHosts, SaneBar, SaneClick (SaneClip was template)
- **GitHub Sponsors added to SaneClick**: Was the only site missing it — added Support section + footer link
- **Cross-sell sections expanded**: All 4 sites now show all 3 sister apps (was 2 each). Copied cross-sell icons between repos. Updated grid to 3-column + mobile breakpoint.
- **Footer links unified**: All 4 sites now have: Guides, GitHub, Privacy, Help, Contact, MIT License, Sponsor, SaneApps
- **SaneBar privacy.html**: Created standalone page (was linking to GitHub PRIVACY.md). Added to sitemap.
- **Contact email**: Added hi@saneapps.com to SaneHosts and SaneClip footers

### GitHub Sponsors Link Fix (from previous context, committed this session)
- Fixed sponsor links from old usernames (stephanjoseph, sane-apps) to MrSaneApps across SaneHosts, SaneBar, SaneClip

### GitHub Issues
- **GasMask #224**: Responded to pushback on SaneHosts recommendation — disclosed developer status, clarified open source/MIT
- **SaneBar #16**: AB-boi reported icon transparency issue (NOT addressed yet)
- **SaneBar #17**: "Always hidden section" feature request — already reopened by you
- **SaneBar #33**: Bartender migration tool — help wanted, 0 community responses

### Orphaned Process Cleanup
- Killed 2 orphaned claude subagent processes burning 200% CPU combined
- Known Anthropic issue — multiple open bugs on github.com/anthropics/claude-code (#17391 is closest match)

## Commits This Session

| Repo | Commits | Description |
|------|---------|-------------|
| SaneHosts | `3a01e52`, `21aff96` | Sponsor link fix + unified SEO/cross-sell/footer |
| SaneBar | `846efb1`, `7039156` | Sponsor link fix + unified SEO/cross-sell/footer/privacy page |
| SaneClick | `3fb0086`, `fbd46f9` | Sponsor link fix + unified SEO/cross-sell/footer/GitHub Sponsors |
| SaneClip | `0b16f49`, `7c00118` | Sponsor link fix + unified cross-sell/footer |

All 4 sites deployed to Cloudflare Pages.

## Pending / Not Done

- **SaneBar icon transparency** (issue #16 from AB-boi) — needs investigation
- **SaneHosts plan from plan mode** (accessibility labels, appcast fix) — plan exists at `~/.claude/plans/reactive-popping-allen.md`, not started this session
- **SaneBar/SaneClip non-website changes** — uncommitted Swift/config changes from prior sessions remain in those repos
- **Remaining audit WARNs**: orphaned images on SaneBar (5 files) and SaneClip (2 files), JSON-LD on subpages, SaneBar javascript:void(0) links on index.html
