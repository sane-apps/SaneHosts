# Session Handoff — SaneHosts

**Last updated:** 2026-05-25

## Current State

- 2026-05-25 18:40 EDT SaneHosts `#4` latest evidence root-caused and patched:
  - Evidence review covered `check-inbox.sh issue-review SaneHosts 4`, latest
    GitHub screenshots, local handoff/research, and the first-run tutorial and
    dark-mode UI source paths. `#5` has no new reporter evidence after `1.1.13`
    and remains waiting for reporter confirmation.
  - Root cause for the still-dark `#4` screenshot was a combination of real
    low-contrast secondary styling and the first-run tutorial spotlight overlay:
    the overlay dimmed the whole window while the tooltip could be positioned
    outside the captured visible area, making normal UI look broken.
  - Fix: core dark UI no longer uses `.secondary`/gray semantics for the affected
    main/profile/detail rows; tutorial overlay now uses local overlay bounds,
    lighter dimming, an opaque black tooltip, white title/body text, and a
    regression policy test for these rules.
  - Verification: Mini `./scripts/SaneMaster.rb verify --timeout 900` passed
    `88` tests. Mini first-run visual smoke passed at
    `outputs/visual_smoke/visual_smoke_20260525-183856_6753/` and the inspected
    `app-see.png` shows the tutorial tooltip visible in-frame. Mini completed-
    tutorial visual smoke passed at
    `outputs/visual_smoke/visual_smoke_20260525-184024_15764/` and the inspected
    `app-see.png` shows the normal main window readable with no visible clipping.

- 2026-05-25 09:33 EDT cross-product launch ops reran canonical Mini
  `launch_readiness`; it exited `1`, so the overdue launch-package lane stayed
  no-go and no scheduling, package-execution, or public posting action was
  executed. Human visual approval plus a public URL are still missing for
  `website/videos/sanehosts-privacy-switch-30s.mp4`, the Product Hunt maker
  comment/day-of checklist still needs exact approval, Mini `release_preflight`
  still carries `4` warnings, and the shared validation report still flags
  SaneHosts customer UI proof as stale and older than 12 hours. Next
  checkpoint: `2026-05-28`. No new public URL was created in this run.
- 2026-05-24 23:35 EDT validation cleanup: strict customer UI contract is
  green locally and Mini `release_preflight` passed with warnings only. Latest
  project QA gate is current again in the global readiness checklist.
- 2026-05-24 Basic/Pro visual and strict UI contract pass:
  - Visual verification found and fixed an Entries table layout regression:
    `255.255.255.255` wrapped in the IP column. `IPAddressText` is now
    one-line/fixed-size and the IP column is `140` points wide.
  - Regression test added:
    `EntryRowLayoutPolicyTests.ipAddressesStayOnOneLine`.
  - Strict customer UI contract then caught a manifest gap:
    `bulk-entry-actions` had fixture/state proof but no screenshot evidence.
    `Tests/CustomerUIActions.yml` now requires `screenshot` for that action,
    guarded by `CustomerUIManifestPolicyTests.bulkEntryActionsRequireVisualEvidence`.
  - Fresh Mini visual receipts inspected:
    `visual_smoke_20260524-192153_63437` in Basic and
    `visual_smoke_20260524-192341_71984` in Pro; the IP row no longer wraps.
  - Mini `customer_ui_sweep --json` generated receipt
    `2026-05-24T23:28:03Z`; strict customer UI contract passed with no issues
    or warnings; Mini `./scripts/SaneMaster.rb verify --timeout 900` passed
    `85` tests.

- 2026-05-15 launch-readiness cleanup:
  - Current direct-download release identity is `1.1.11` (build `1111`), matching `Config/Shared.xcconfig`, README, and `website/appcast.xml`.
  - `.saneprocess` now marks the website lane as active with `website_domain: sanehosts.com`.
  - `scripts/customer_ui_action_sweep.rb` was updated to emit the current structured customer UI receipt schema required by SaneProcess.
  - Mini customer UI sweep now passes with 11 covered actions, and Mini release preflight passes with warning-level cleanup only.
  - The 30-second privacy-switch video was staged to `website/videos/sanehosts-privacy-switch-30s.mp4` with SHA-256 `7132b6758a8c1505d76a410b9f951912a57d909c5454660154df5568421c264e`.
  - Remaining launch blockers are marketing/public-action gates: human visual approval and public deploy for the video, plus final Product Hunt maker comment and day-of checklist approval.

- 2026-05-12 customer-facing action release gate is now recorded for SaneHosts:
  - Added `Tests/CustomerUIActions.yml`, `scripts/customer_ui_action_sweep.rb`, and `.sane/customer_ui_action_receipt.json`.
  - `./scripts/SaneMaster.rb customer_ui_contract --no-exit` passes with 11 required actions covered; receipt generated `2026-05-12T03:45:56Z` on host `mini`.
  - Mini `./scripts/SaneMaster.rb verify` passed 82 tests.

- Current direct-download release is `1.1.11` (build `1111`).
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

- 2026-05-24 SaneHosts `#4`/`#5` patch candidate: UI text was brightened across the main/profile/settings/coach-mark surfaces for Tahoe readability, and `ProfileStore` now creates Essentials even after migration has already created "Existing Entries" so Basic users keep the included profile. Latest Mini `./scripts/SaneMaster.rb verify --timeout 900` passed with `85` counted tests after the IP wrap and strict visual manifest fixes. Worker runtime visual receipt: `outputs/visual-audit-sanehosts-20260524/sanehosts-runtime-after-fix-20260524.png`.
- **SaneBar icon transparency** (issue #16 from AB-boi) — needs investigation
- **SaneHosts plan from plan mode** (accessibility labels, appcast fix) — plan exists at `~/.claude/plans/reactive-popping-allen.md`, not started this session
- **SaneBar/SaneClip non-website changes** — uncommitted Swift/config changes from prior sessions remain in those repos
- **Remaining audit WARNs**: orphaned images on SaneBar (5 files) and SaneClip (2 files), JSON-LD on subpages, SaneBar javascript:void(0) links on index.html

## Launch Ops Calendar - 2026-05-14

- `.outreach.yml` now classifies SaneHosts as `released_niche_launch_not_scheduled`.
- Scheduled gates: launch package on 2026-05-24 and launch decision on 2026-05-28. Position around privacy/security and direct-only architecture; do not imply App Store availability.
- 2026-05-14 launch package update: website hero proof now explains why SaneHosts is a direct Mac download and why macOS asks for Touch ID/password before hosts-file changes. Generated local Product Hunt candidate assets at `website/images/product-hunt-thumbnail-240.png` and `website/images/product-hunt-gallery-01.png` through `03.png`, plus `Videos/sanehosts-privacy-switch-30s.mp4` (1920x1080, 30.0s). Current launch gate remains no-go until visual approval/hosting, final maker comment/day-of checklist, and fresh green Mini release proof.

## Launch Ops Calendar - 2026-05-15

- Mini `./scripts/SaneMaster.rb launch_readiness` returned nonzero for SaneHosts. No Product Hunt, Show HN, directory, or public reply action was taken.
- Blockers recorded from the gate: the privacy-switch video is still local-only and needs human visual approval plus hosting, the Product Hunt maker comment/day-of reply checklist still needs exact approval, and the latest launch-gate `release_preflight` is not green in this context (124 issues, 4 warnings).
- Existing support-surface URLs remain unchanged: [awesome-mac](https://github.com/jaywcjlove/awesome-mac/pull/1804) and [awesome-macOS](https://github.com/iCHAIT/awesome-macOS/pull/713).
- Next launch-ops date stays 2026-05-24 for package prep only.

## Launch Ops Calendar - 2026-05-16

- Mini `./scripts/SaneMaster.rb launch_readiness --json` stayed red for SaneHosts, so no Product Hunt, Show HN, directory, or public reply action was taken.
- Fresh blocker receipt: the privacy-switch video still needs human visual approval plus hosting, the Product Hunt maker comment/day-of reply checklist still needs exact approval, and the launch package is still incomplete even though `release_preflight` remains green with 3 warnings.
- Existing support-surface URLs remain unchanged: [awesome-mac](https://github.com/jaywcjlove/awesome-mac/pull/1804) and [awesome-macOS](https://github.com/iCHAIT/awesome-macOS/pull/713).
- Next launch-ops date stays 2026-05-24 for package prep only.

## Launch Ops Calendar - 2026-05-17

- Mini `./scripts/SaneMaster.rb launch_readiness --json` stayed red again for SaneHosts, so no Product Hunt, Show HN, directory, or public reply action was taken.
- Fresh blocker receipt: the privacy-switch video still lacks human visual approval and a hosted public URL, the staged `website/videos` asset is not deployed publicly yet, the Product Hunt maker comment/day-of reply checklist still needs exact approval, and `release_preflight` remains warning-only with 3 warnings.
- Existing support-surface URLs remain unchanged: [awesome-mac](https://github.com/jaywcjlove/awesome-mac/pull/1804) and [awesome-macOS](https://github.com/iCHAIT/awesome-macOS/pull/713).
- Next launch-ops date stays 2026-05-24 for package prep only.

## Launch Ops Calendar - 2026-05-18

- Mini `./scripts/SaneMaster.rb launch_readiness` stayed red again for SaneHosts, so no Product Hunt, Show HN, directory, or public reply action was taken.
- Fresh blocker receipt: the privacy-switch video still lacks human visual approval and a hosted public URL, the staged `website/videos` asset is not deployed publicly yet, the Product Hunt maker comment/day-of reply checklist still needs exact approval, and `release_preflight` remains warning-only with 3 warnings.
- Existing support-surface URLs remain unchanged: [awesome-mac](https://github.com/jaywcjlove/awesome-mac/pull/1804) and [awesome-macOS](https://github.com/iCHAIT/awesome-macOS/pull/713).
- Next launch-ops date stays 2026-05-24 for package prep only.
