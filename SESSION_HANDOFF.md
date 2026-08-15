# Session Handoff — SaneHosts

**Last updated:** 2026-08-14 23:05 EDT

## 2026-08-14 sticky helper writes

`com.mrsane.SaneHostsHelper` is SMAppService **enabled** on the Mini.
Writes through that helper no longer add a LocalAuthentication password
on every activate (the helper already runs as root and checks the
signed app). AppleScript fallback still asks if the helper is down.
Launch opens Login Items only when status is `requiresApproval`.
Verify: 123 tests, receipt `3dcf615fe92bf8818dd6418ed76fa45e`.

## 2026-08-14 empty Essentials

Live Mini Essentials was a 0-entry stub from first launch (no bundled
lists, local-only load, empty profile saved forever). Source now refills
an empty Essentials from cache/network and will not persist another
blank stub. Signed Release relaunch refilled **99,061** entries.
Visual: `outputs/visual-audit-20260814-essentials/`. Mini verify 122
tests, receipt `f203ce9590cfd05eb2c1d4f47157ace5`.

## 2026-08-14 1.1.25 publish attempt

- 1.1.25 (build 1125) is on `origin/main` at `08cd61a`. Live Sparkle is still 1.1.24.
- Did not ship. `release_preflight` failed: stale customer-UI receipt (2026-07-27 artifacts missing) and no upgrade-path proof.
- Mini `customer_ui_action_executor.rb --execute` built and launched, then failed on onboarding: `No visible AX control matched: Next`.
- Left the uncommitted `shouldShowExpiredTrialGate` edit uncommitted; current SaneUI pin `7f87b04` does not have that API.

## IN PROGRESS: DNS fallback + disabled close-control patch (2026-08-04)

- Customer report reproduced from the exact warning and screenshot. The direct
  AppleScript fallback elevated only the `/etc/hosts` copy, then ordinary-user
  `DNSService` tried `/usr/bin/killall -HUP mDNSResponder` and deterministically
  received exit 1. Source now performs the copy, `dscacheutil -flushcache`, and
  `mDNSResponder` HUP inside the same existing administrator-authorized command,
  returns DNS success separately, and preserves truthful partial-success warnings.
- The disabled red close control was a second bug. The shared license gate can
  remove `.closable`, then cached license restoration can replace the gate before
  its timing-sensitive restore runs. Normal SaneHosts workspace entry now
  reasserts the close-control contract on the next main-loop turn. An actual
  `NSWindow` regression test covers disabled-to-enabled restoration.
- `DNSService.lastFlushDate` now updates only after both cache operations pass.
  Package/test SourceKit diagnostics are clean and `git diff --check` passes.
- The next controlled AgentMemory gate passed: the one permitted canonical
  installer attempt restored Mini `livez`, and CLI status reports connected,
  healthy version 0.9.28. Canonical Mini verification then passed 118 tests,
  including the new privileged-DNS and real-`NSWindow` close-control regressions,
  with receipt `fe64b8833692a68b8907b2a127a3ab05`.
- Version is now 1.1.25 (build 1125), but no public release has happened yet.
  Canonical lint is green (`96e48cb5c3d8070eeb8b770940df1890`), and the
  post-format/split Mini suite is green at 118 tests
  (`f96d1557b74bc8ff835743c5e20751aa`). The lint repair adds the first project
  SwiftFormat baseline, excludes generated outputs/checkouts, and moves the
  entry-row/sheet helpers out of the former 1,002-line `ProfileDetailView`.
- The exact signed Release app was built, staged, and launched from
  `/Applications/SaneHosts.app` as 1.1.25/1125
  (`31f5f3b45a6bb6d9d37de0bbf9bb2be6`). AX read-back reported the close control
  enabled; pressing it left the menu-bar process alive with zero windows; Open
  SaneHosts restored one window with the close control enabled; Quit SaneHosts
  terminated the process. Strict code-sign verification passed. Clean visual
  smoke passed (`d8962c25730b05a70538a49ac56363ad`).
- The Mini has no installed `com.mrsane.SaneHostsHelper`, so a real profile
  switch correctly targets the fixed AppleScript fallback but still requires a
  human macOS administrator approval. The exact privileged copy-plus-DNS command
  is regression-covered; post-approval live activation remains the only
  unattended runtime proof gap. The full `/ship` checkpoint and mandatory user
  release gate remain required.
- The post-SaneUI-pin candidate suite remains green at 118 tests with receipt
  `647d1efeb61760b8e1fbc133f0905f58`; canonical lint is green with receipt
  `6a34d84b7019251b04fdf59ba55bc45c`. The first fresh 11-action executor run
  rebuilt and staged the signed Release app, then reproduced the older tooling
  failure at `menu-bar-profile-actions` (`show_menu returned -25200`). Diagnosis
  proved the driver had selected the ordinary app menu named `SaneHosts`; the
  real SwiftUI menu extra is an `AXMenuExtra` exposed as `status menu` and
  advertises only `AXPress`. The executor now targets role + subrole + exposed
  description, queries supported AX actions, and falls back from supported
  `AXShowMenu` to supported `AXPress`. The first corrected-selector run then
  proved the ordinary `AXChildren` walk does not expose the extra; Apple
  provides it through the application-level `kAXExtrasMenuBarAttribute`.
  Control lookup and post-action readback now traverse explicit app-menu and
  extras-menu roots as well as the normal tree. Raw Mini read-back then proved
  the stable item identity is the SF Symbol title prefix `network`, not the
  lossy System Events description `status menu`. Pressing that exact item can
  return documented `kAXErrorCannotComplete` while successfully opening its
  modal menu, so bounded post-action readback is now authoritative. A targeted
  patched-driver proof passed against the live candidate: it matched control
  `network.badge.shield.half.filled` and read back both `Open SaneHosts` and
  `Quit SaneHosts`. Focused tests pass 15 runs / 181 assertions and the Swift
  driver type-checks. One full clean-checkout live run is still required before
  release preflight can pass.
- The full `cd81e0a` sweep then passed its first four action groups (onboarding,
  status-menu profile actions, Dock/app-menu commands, and paid-access gates)
  before a distinct `profile-lifecycle-actions` context-menu failure. Raw AX
  inspection proved the generic selector chose a matching menu-bar profile
  command (`AXMenuItem` with Press/Pick) ahead of the visible sidebar summary
  (`AXStaticText` with `AXShowMenu`). Ordinary context-menu requests now prefer
  candidates that advertise `AXShowMenu`; Press fallback remains restricted to
  the explicitly constrained `AXMenuExtra`. A targeted live proof passed on a
  sidebar profile, matching `Essentials, inactive, 0 entries` and reading back
  `Duplicate`, `Export`, and `Delete`. Focused tests now pass 16 runs / 187
  assertions. One fresh clean-checkout full sweep remains required.
- The following clean sweep reached the merge workflow and exposed two more
  proof defects. Substring matching could choose `Merge Profiles` or a child
  `AXImage` instead of the real `Merge` button, and the lifecycle plan toggled
  the duplicate off even though duplication had already selected it. The AX
  driver now ranks exact identity matches, then semantic press controls that
  advertise `AXPress`. The plan asserts the duplicate's inherited `Deselect`
  state, selects only the original, and requires the exact merged sidebar
  summary rather than text already present in the sheet. A targeted replay
  created a real merged profile through the `AXButton`; focused coverage is
  green at 17 runs / 201 assertions and the driver type-checks. The remaining
  gate is one clean full 11-action Release sweep.
- The next exact-Release sweep passed onboarding and the status-menu group,
  then the visual guard rejected the Dock/app-menu screenshot because ChatGPT
  had become frontmost. All Dock/app-menu AX mutations had passed and executor
  cleanup was green; this was evidence-capture focus drift, not a product
  failure. A targeted test proved AppKit activation was accepted without
  actually transferring focus, while the canonical System Events path keyed
  by bundle ID moved Finder -> SaneHosts. The executor now bounds that command
  at the process level, verifies the frontmost result, and repeats the final AX
  state readback before every screenshot. Integrated live proof passed
  (`before=Finder`, AX `QUICK ACTIONS`, `after=SaneHosts`); focused tests are
  green at 19 runs / 216 assertions. One clean full sweep is still required.
- With focus fixed, the next sweep also captured Dock/app-menu actions but the
  paid-gate state exposed multiple SaneHosts window IDs, so the screenshot
  helper emitted suffixed paths and the executor correctly refused the missing
  canonical path. Visual inspection proved the meaningful image contained the
  Merge sheet while a tiny auxiliary image was blank. A second live dialog
  replay produced two substantial but byte-identical warning captures. The
  executor now keeps strict app-scoped all-window capture, filters tiny
  auxiliary surfaces, deduplicates by SHA-256, and normalizes only when exactly
  one unique substantial image remains; distinct real windows still fail
  closed. Targeted SHA normalization produced the canonical 257 KB dialog image
  (`58f3f1be8c922ab9fa822c61299d0792b72dc884ee244cbc7336f85e42cdf5cf`).
  Focused tests are green at 20 runs / 222 assertions; full sweep remains pending.
- The following full sweep passed that paid-gate capture, then the fixture
  profile was persisted but not visible for its context action. This exposed a
  real first-launch product race: the live log recorded two simultaneous
  `load()` paths, two migrations, two `Existing Entries`, and two `Essentials`
  creations. `MenuBarProfileStore` and `MainView` both invoke the shared store;
  `ProfileStore.load()` now coordinates them through one in-flight task so all
  callers await the same initialization. A concurrent 2,000-entry regression
  asserts one of each default and two persisted profile files. Canonical Mini
  verify is green at 119 tests with receipt
  `08cfd08d23e4370b1302358bbde988ce`. A fresh full Release sweep remains pending.
- The next sweep proved the load fix live (`load() started` once plus one
  `Joining in-flight` caller) and reached the real merge. Disk contained the
  exact `UI Proof Profile + UI Proof Profile 1` with merged `sourceCount: 2`;
  only its sidebar AX label was offscreen after five rows. The executor now
  pairs an AX responsiveness readback with a bounded exact persisted-name and
  two-source assertion. That assertion passes on the real failed-run fixture;
  focused coverage is green at 21 tests / 227 assertions. Full sweep remains pending.
- The following sweep passed exact merge persistence and export, then exposed
  two exact `Delete` menu items: the first disabled and the second enabled.
  Action targeting now excludes disabled controls and uses `AXPick` for profile
  context menu commands, which opened the real confirmation and read the strict
  `This action cannot be undone` text. The native alert's enabled Cancel button
  advertises Press but returns `kAXErrorAttributeUnsupported`; the driver uses
  a role-constrained System Events click for that one malformed control and
  retains AX post-action readback as authority. Targeted Delete -> confirmation
  -> Cancel passed with the profile preserved. Focused tests are green at
  22 runs / 240 assertions; full sweep remains pending.
- Globally excluding `AXEnabled == false` fixed Delete selection but regressed
  the first onboarding request because the only first-run button can report a
  disabled accessibility state while still being the actionable surface. The
  driver now prefers enabled matches whenever any exist, then falls back to the
  matched set only when none are enabled. This keeps the enabled Delete item
  authoritative without losing onboarding. A brand-new isolated-home Release
  replay selected a real SaneHosts `AXButton` and read back `QUICK ACTIONS`.
  The onboarding plan now requires role `AXButton`, preventing an unrelated
  macOS `Show Next Tab` menu item from satisfying `Next`. Focused coverage is
  green at 23 tests / 243 assertions; driver type-check and diff check pass.
  One full clean 11-action sweep remains the release-evidence gate.
- The next clean Release sweep proved the remaining onboarding failure was a
  fixture-state bug, not target selection. Its failed fixture immediately read
  `QUICK ACTIONS` but exposed no welcome button: `CFFIXED_USER_HOME` isolated
  files and DerivedData while the launched app still read the user's completed
  onboarding state through `cfprefsd`. The executor's `defaults write` calls
  could also touch the real preference domain. They are removed. A process-only
  `SANEHOSTS_CUSTOMER_UI_FIXTURE` override now presents the welcome sheet from
  local state, forces Dock visibility in memory, and is restored during cleanup.
  The action plan clicks all six `Next` buttons with page-specific readbacks,
  then `Continue Trial` or `Start Using SaneHosts`; it no longer substitutes an
  unrelated main-window button for onboarding. Focused coverage passes 24 tests
  / 263 assertions. Canonical Mini verification passes 120 tests with receipt
  `865f2e961661b89157b0945aa6c26ef0`; lint receipt
  `eac57d2159bb87f1d2e7403cb0cecd3f`. A clean full Release sweep remains.
- The first deterministic-welcome sweep traversed all six `Next` pages, then
  stopped because its final-page alternatives were encoded as two required
  groups (`14-Day Trial` AND `You're all set`) instead of one OR group. Cleanup
  passed with zero processes and all environment values restored. The corrected
  nested OR contract has a regression assertion (24 tests / 264 assertions).
  A targeted signed-Release replay then matched, in order, every welcome page,
  `You're all set`, `Start Using SaneHosts`, and final `QUICK ACTIONS`, using
  only real `AXButton` controls. The remaining gate is the complete sweep.
- The next full sweep passed onboarding, status-menu, Dock/app-menu, paid-gate,
  and the complete profile lifecycle before `Family Safe` was below the
  virtualized sidebar fold. A native AX scroll helper now walks from visible
  sidebar headings to their owning `AXScrollArea` and sets the numeric vertical
  scrollbar value; exact readback must expose the destination. That revealed a
  product accessibility defect: the labeled protection-level row was
  `AXStaticText`, and AXPress returned success without invoking its tap gesture.
  The row now exposes the button trait plus an accessibility action with the
  same paid/unlocked routing. Targeted signed-Release proof passed
  `PROFILES -> Family Safe -> Add Family Safe -> PROTECTION LEVELS -> From
  Template -> Create from Template`, using `AXHeading`/`AXButton` controls.
  Focused coverage passes 25 tests / 277 assertions; canonical Mini verification
  passes 121 tests, receipt `23a9ed6f6af26465359a5dd258ad25e7`;
  lint receipt `ceafb910c8a87e4eca505310ba5ad6ac`. Full sweep remains.

## SHIPPED: 1.1.24 direct release — execution proof refresh pending

- 2026-07-30: PRs #7 and #8 merged the real external execution-evidence
  contract and the Mini-only 11-action accessibility executor. The focused
  runner tests passed 12/162 and 10/26; the full Mini suite passed 117 tests
  with receipt `c544712be28cd18a5eccdd903727eee0`.
- SaneProcess PRs #28 and #29 fixed Release provisioning parity and isolated
  `CFFIXED_USER_HOME` DerivedData discovery. Their focused tests passed 28/28
  locally and on the Mini. The live executor now builds, signs, stages, and
  launches the exact Release app with a live log attached before launch.
- The 2026-07-30 live run completed
  `onboarding-and-tutorial-entry`, saved a clean screenshot, then stopped on
  `menu-bar-profile-actions`: the AX driver returned
  `show_menu returned -25200`. Evidence:
  `outputs/customer-ui/sweep-20260730T070224Z/execution-failed.json`,
  `visual/onboarding-and-tutorial-entry.png`, and
  `cleanup-receipt.json`. Cleanup passed with zero owned processes left.
- The screenshot is clean and readable, but the trial helper line is visibly
  truncated. The remaining ten actions are unproved. Do not rerun without
  first diagnosing the AX menu failure; do not claim full customer-action
  clearance or republish `1.1.24`.

- Version `1.1.24` (build `1124`) shipped on 2026-07-27. GitHub release
  `v1.1.24` is public; its release tag points to
  `508eb958616a3670df4db5ecebdc49214feaf144`. Current `origin/main`
  (`df17cdbab247641ef295a7b48bc1ee69cb00c3c4`) differs only in
  release/site metadata, not app source. The release ledger records appcast,
  website, webhook, Homebrew cask, and Lemon Squeezy at `1.1.24`.
- Version `1.1.24` pins SaneUI to
  `7a06370f1712552c4d0e3e0860b19bf22175e3d6` and replaces current
  Basic/Pro tier copy with the 14-day trial, then one-time purchase model.
  Current app UI, README, privacy copy, website, release metadata, and
  customer-action tests use neutral trial and paid-access language. This
  supersedes older Basic/Pro source-of-truth notes below without rewriting
  their historical record.
- Canonical Mini verify passed `117` tests:
  `0b816afd532953600ec359df9504627d`. Focused source-policy and docs checks
  passed: `ca789d910f52af369fbfd20ecb837c5f`.
- Live expired-trial gate passed on the Mini:
  `ae13667f37f2d271c5203ccb3cada69a`. Evidence:
  `outputs/visual-audit-trial-expired/1.1.24/sanehosts-expired-trial.png`
  and `outputs/live-logs/sanehosts-expired-trial-20260727.log`.
  Visual verdict: clean, bright, no clipping, and no tier language.
- The old customer UI action sweep generated its own click transcript and
  copied manifest steps into `steps_completed`; that receipt does not prove
  those actions ran. The replacement runner refuses synthetic completion
  claims and requires an external, fresh Mini execution receipt with a real
  click artifact and distinct screenshot for every action. It also binds the
  run to the exact manifest hash, source fingerprint, SaneHosts commit,
  SaneUI commit, live log, functional state, inputs, assertions, and safe
  boundary results.
- Remaining proof boundary: run the external Mini UI executor across every
  release-required action and ingest its receipt with
  `scripts/customer_ui_action_sweep.rb --execution-evidence PATH`. Until that
  succeeds, the older customer-action receipts are historical evidence only,
  not current full execution proof. This is post-release proof repair; do not
  republish `1.1.24`.
- Fresh Mini pre-push and preflight verification passed `117` tests; verify
  receipts: `e4a312030a405b0fa7bcccdfadfdd1ee` and the receipt embedded in the
  signed preflight above.
- The older Worker deployment receipt
  `9175e22a-8977-4345-91be-1da97067e783` predates the `1.1.24` release and
  must not be used as current download-version proof.
- Audit fixes are implemented: neutral shared direct-trial onboarding, current
  shared accent, included-profile copy, clear one-time pricing, required
  website trust badges, and a 13px minimum for site helper text.
- SaneUI full Mini tests passed 132 tests across 28 suites. SaneHosts full Mini
  verify passed 117 tests after pinning the final shared fix; receipt
  `55568261ad9949c39977f3176cbff238`.
- All seven first-run screens were exercised on the Mini with a live log.
  The complete evidence set is in
  `outputs/visual-audit-neutral-trial/1.1.24/`. Final corrected receipts:
  `final-page2-walkthrough.png` and `final-page7-trial-summary.png`.
  Verdict: bright, balanced, clear, and unclipped; the final trial action is
  explicitly labeled `Continue Trial`.
- The real `Continue Trial` action dismissed setup, preserved the active
  14-day trial, and opened the normal first-use tutorial. Result screenshot:
  `final-after-continue-trial.png`; live log:
  `outputs/live-logs/sanehosts-onboarding-conversion-final-20260727.log`.
- Customer UI action sweep and contract pass after the audit fixes; contract
  receipt `afe0ad57c664cebb780a6ad74bc2ce9c`.

## SHIPPED: 1.1.22 large-profile activation fix LIVE on Sparkle channel

- **SaneHosts 1.1.22 is live on the Sparkle channel** (2026-07-15): the
  appcast serves `SaneHosts-1.1.22.zip` with the large-profile fix release
  note (bump `81509da`, metadata sync `5dcfd0e`). Pre-ship real-data proof:
  the actual Steven Black Unified list (76,158 entries, 10.7 MB persisted)
  ran parse → persist → summary reload → hydration → hosts generation, all
  green. **Remaining owner step:** the LS dashboard-hosted file still serves
  1.1.19 — publish the 1.1.22 ZIP (product 794910 → variant 1253740) from
  `https://dist.sanehosts.com/updates/SaneHosts-1.1.22.zip`, unpublish old
  files, then rerun `release.sh --project ~/SaneApps/apps/SaneHosts
  --version 1.1.22 --post-release-checks-only`. This supersedes the 1.1.21
  LS step below.
- **Post-ship refactor (`9f0582f`):** ProfileStore.swift split 1,201 → 736
  lines (Rule #10) into `LargeProfileSummaryLoader` /
  `ProfileDirectoryLoader` / `ProfileBackupArchive` / `ProfileStoreError`
  collaborator files, behavior unchanged. New `lastHydrationIssue` records
  the last hydration failure (cleared on the next success) and is surfaced
  in the diagnostics settings summary, with a behavioral test — Glenn's
  feedback payloads previously carried no trace of hydration failures.
  Mini verify 114 tests green; customer UI sweep passed (receipt
  2026-07-15T14:28:19Z). The
  `largeProfileLoadingUsesSummariesAndImportBounds` policy test now scans
  the new file boundaries.
- Glenn consolidated reply (#1136/#1139/#1141) is drafted at
  `~/SaneApps/outputs/glenn-1139-1141-consolidated-reply.txt` and awaits
  owner approval; the media-review gate still needs the documented
  exception (see caveat below).

## Source history: Glenn large-profile activation failures (shipped in 1.1.22)

- Glenn's July 14-15 support emails `#1139` and `#1141` showed the same failure
  for Kitchen Sink and Steven Black Unified: activation tried to open a profile
  JSON file named after an entry UUID that never existed. Reproduced against a
  real 61 MB profile. The large-profile summary reader was finding the first
  nested `entries[].id` instead of the top-level profile `id` whenever encoded
  key order put `entries` first.
- `ProfileStore` now treats the profile filename UUID as canonical, validates
  stored IDs on every load/hydration path, quarantines malformed or mismatched
  files, and refuses to save a 100-entry partial summary over the full profile.
  Reordering hydrates before writing, closing the adjacent data-loss risk.
- Added `ProfileStoreLargeProfileTests`: both JSON key orders, reload and full
  hydration, malformed/mismatched identity recovery, partial-save protection,
  and reorder preservation. Mini `SaneMaster verify` is green: **113 tests**,
  receipt `f607dda3fb263faaa4526ad33907689e`.
- Easy wins shipped in source with the repair: the UI now says protection stays
  active after SaneHosts closes/quits, says exactly how deactivation/profile
  switching is authenticated, labels the action `Turn Off Protection…`, keeps
  user-cancelled authentication quiet, and routes profile deletion through a
  confirmation. The existing Pro padlock fix remains covered.
- Runtime proof on the Mini: customer action sweep **11/11 green**, receipt
  `00735bebcfee5a95d20c2acd0eadcb42`; isolated visual smoke **green**, receipt
  `5959fa99bde4d91a616f1979b1b45ce5`; clean capture at
  `outputs/visual-audit-glenn/visual_smoke_20260715-074808_98547/app-see.png`.
  The live log has no activation/file-identity/partial-profile errors.
- No release or customer email has been sent. Recommend shipping this as
  **1.1.22** (Sparkle requires a new version), then send one consolidated reply
  to Glenn and ask him to retest both lists. A separate parent-only passcode is
  deliberately deferred: current behavior persists through quit/restart and
  uses Touch ID or the Mac account password, but is not a tamper-proof parental
  control boundary.
- Support-media caveat: the current inbox classifier skipped Glenn's inline
  screenshots as decorative, so `confirm-media-review` cannot issue its normal
  semantic receipt even though the screenshots were manually downloaded and
  inspected. Keep `#1139` and `#1141` open; do not reply/resolve until the gate
  has a valid receipt or the owner explicitly approves the documented exception.

## SHIPPED: 1.1.21 Sparkle channel LIVE

- **SaneHosts 1.1.21 is live on the Sparkle auto-update channel**
  (`sanehosts.com/appcast.xml` serves `SaneHosts-1.1.21.zip` + the padlock
  release note). This is the path "Check for Updates" uses — Glenn can update
  now. Build signed + notarized + deployed via `release.sh --full --deploy`
  from the Mini GUI session; git tag/appcast/site/webhook all updated.
- **ONE owner step remains:** the LemonSqueezy dashboard-hosted file (direct
  download / new purchases) still serves 1.1.19. Replace it via the LS
  dashboard: product 794910 → Files for variant 1253740 → publish the 1.1.21
  ZIP from `https://dist.sanehosts.com/updates/SaneHosts-1.1.21.zip`, unpublish
  old files. Then rerun `release.sh --project ~/SaneApps/apps/SaneHosts
  --version 1.1.21 --post-release-checks-only` to confirm green. (This is the
  standing manual per-release LS step, not a new bug.)
- The older standalone Glenn `#1136` padlock reply is superseded by the pending
  consolidated response covering `#1136`, `#1139`, and `#1141`.


## Current State

- 2026-07-14 **Pro padlock fix + 1.1.21 release in flight.** Customer report
  (Glenn, work-email #1136, redeemed the THANKSGLENN comp same day): the
  sidebar "PRO FEATURES" header kept its closed padlock after Pro activation.
  Fixed in `d0bf8e1` — header renders `ProFeature.sectionIcon(isPro:)`
  (`lock.open.fill` when Pro); Swift Testing regression
  (`ProSectionIconTests`); routed verify green 103 tests; runtime proof
  screenshot on the Mini: `~/Desktop/Screenshots/sanehosts-padlock-pro-proof-20260714.png`
  (open padlock, Pro-mode launch). Cross-app sweep: only SaneHosts affected.
- 2026-07-14 **Version bumped to 1.1.21 (1121)** in `Config/Shared.xcconfig`
  (`18edf6c`): 1.1.20 channel artifacts (appcast/site/webhook/tap) were
  already rolled out WITHOUT the padlock fix (LemonSqueezy hosted file still
  1.1.19), and Sparkle ignores same-version updates.
- 2026-07-14 **Sweep tooling fix (`c40ba15`):**
  `scripts/customer_ui_action_sweep.rb` now parses the customer UI contract
  JSON from stdout only (`Open3.capture3`); `capture2e` merged SaneMaster's
  stderr Ruby re-exec notice into the payload and broke the sweep under the
  Mini GUI-session PATH. Sweep passed after the fix (receipt at
  `.sane/customer_ui_action_receipt.json` on the Mini).
- 2026-07-14 **Release lane state:** run preflight/release via
  `mini-gui-run.sh` on the Mini (plain SSH sessions see a locked keychain →
  "release authorization key is unavailable" / codesign
  errSecInternalComponent). The Mini checkout's stray working-tree deletions
  (incl. `SaneHosts.xcworkspace/contents.xcworkspacedata`) were restored —
  their absence made verify fall back to a project-only invocation with "no
  test bundles available". Preflight round 3 running; next: release.sh
  --full --deploy (1.1.21), live-appcast check, owner-approved reply to
  Glenn (#1136) asking him to update and verify.

- 2026-06-27 **Keychain prompt-storm fix (data-protection keychain) — staged for
  the next release.** Background: SaneApps store the license/trial in the legacy
  login keychain, whose per-item ACL is bound to the build's code signature, so a
  Developer ID app re-prompts ("wants to use your confidential information") on
  every item after an update changes the signature (TN3137). Fix:
  - SaneUI `KeychainService` gained an opt-in `accessGroup` → data-protection
    keychain + one-time legacy→DP migration (committed/pushed, revision
    `f8e5274`; 117 tests). SaneHosts SaneUI pin bumped to `f8e5274`.
  - SaneHosts injects the access group via the existing `LicenseService(keychain:)`
    param (`SaneHostsLicenseKeychain`, group `M78L6FXD48.com.mrsane.SaneHosts`).
  - Added the `keychain-access-groups` entitlement + **manual Developer ID
    signing** in `Config/Shared.xcconfig` (scoped to the app; helper stays
    Automatic). The entitlement is restricted and needs a provisioning profile.
  - Created the `com.mrsane.SaneHosts Direct` Developer ID profile via the ASC
    API (`fastlane sigh --developer_id`), installed on the Mini. No App-ID
    capability toggle was needed (Developer ID profiles auto-carry `M78L6FXD48.*`).
  - Verified: `verify` passes 101 tests against the pinned remote SaneUI; the
    signed build reaches codesign and **BUILD SUCCEEDED** (the config cleared the
    "requires a provisioning profile" error).
  - **NOT yet verified (needs a GUI session / the release):** the actual SIGNED
    build can't run over headless ssh ("User interaction is not allowed" for the
    signing key without `KEYCHAIN_PASSWORD`). The signed build + notarization
    happen at release time via `release.sh` (which already does
    `signingStyle: manual` + a `provisioningProfiles` map). The runtime behavior
    (no prompt + license migrates) should be spot-checked on a real machine after
    the release. The owner observed the storm on a real install.
  - Replication to SaneBar/SaneClick/SaneClip/SaneSync uses the same recipe
    (sigh profile → entitlement + manual-signing xcconfig → inject SaneUI group).
    See memory `sanehosts-keychain-dp-migration`.

- 2026-06-27 keychain prompt-storm pilot (UNCOMMITTED, not released):
  - Problem: after an update, macOS hammers users with "wants to use your
    confidential information" keychain prompts. Root cause: SaneUI stores the
    license + trial timestamps in the legacy login keychain (per-item ACL bound
    to the creating build's code signature); a signature change re-prompts on
    every item every launch. Dev-machine artifact today; becomes fleet-wide the
    day the signing cert rotates. Full analysis + cross-app impact in memory
    `sanehosts-keychain-dp-migration` (also affects SaneBar/SaneClick/SaneClip/
    SaneSync; SaneVideo/SaneSales sandboxed = safe).
  - Fix (opt-in, pilot on SaneHosts): SaneUI `KeychainService.init(service:
    accessGroup:)` — when accessGroup set, use data-protection keychain +
    `kSecAttrAccessGroup` + one-time legacy->DP migration; default nil leaves
    every other app unchanged. `LicenseService` UNCHANGED (injected via its
    existing `keychain:` param). New `SaneHostsLicenseKeychain` (service
    `com.mrsane.SaneHosts`, group `M78L6FXD48.com.mrsane.SaneHosts`) injected at
    all 3 LicenseService sites; added `keychain-access-groups` entitlement.
  - Proven on Mini: `SANEHOSTS_USE_LOCAL_SANEUI=1 verify` -> 101 tests; SaneUI
    `swift test` -> 117 tests incl. new data-protection query test; signed
    test_mode build succeeds (entitlement wired via Shared.xcconfig).
  - PENDING: live runtime proof (no-prompt + migration; keychain is bypassed in
    tests) on Mini then the Air (real broken-ACL license), then bump SaneHosts
    SaneUI pin + release, then roll to the other 4 affected apps.
  - Infra fixes (also uncommitted, in SaneProcess): trimmed stale GitHub/Context7
    from MCP-verification gate (`sanetools_research.rb`); added
    `SANEHOSTS_USE_LOCAL_SANEUI` to SaneMaster `forwarded_env_keys`.

- 2026-06-21 direct-download release `v1.1.17` shipped and deployed:
  - Version bumped to `1.1.17` / build `1117` in `Config/Shared.xcconfig`.
  - Paid users are not impacted: `LicenseService.hasExpiredProTrial` is false
    when a valid license is active. Active-trial users keep the workspace and
    see a left-rail countdown/Upgrade card. Expired-trial users see the shared
    `LicenseGateView` with Buy Now and Enter License Key actions.
  - Menu bar profile activation now routes expired-trial users back to the main
    upgrade gate instead of activating a profile from the menu.
  - New policy tests: `expiredTrialRequiresPaidUpgrade` and
    `trialCountdownCopy`. Mini `./scripts/SaneMaster.rb verify --timeout 900`
    passed `99` tests after the trial change, after the customer UI contract
    update, and after the version bump.
  - Visual proof inspected locally:
    `outputs/visual-audit-trial-active/direct/sanehosts-active-trial.png`
    shows “25 days left in Pro trial” with an Upgrade action while the app
    remains usable; `outputs/visual-audit-trial-expired/direct/sanehosts-expired-trial.png`
    shows the tactful expired-trial upgrade/license gate.
  - Mini `customer_ui_sweep --json` passed after the version bump and before
    release with receipt timestamp `2026-06-21T09:05:18Z`, source fingerprint
    `4c0bfdbd26fd19197f133a0b8d40b8487d6bd9fe164f9e673a4df15588c12f1f`,
    and live log `outputs/live-logs/customer_ui_sanehosts_20260621T090419Z.log`.
  - Release commits on `main`: `3d5507e` simplified SaneHosts and added the Pro
    trial gate, `5d88ed1` bumped version metadata, `363d4f2` restored appcast
    compatibility after the cleanup pass, and `08bd021` synced release metadata.
    Tag `v1.1.17` points at `363d4f2`.
  - Release artifact:
    `https://dist.sanehosts.com/updates/SaneHosts-1.1.17.zip` with SHA-256
    `30f35dc82f7152447ebee087291a1ebb762da3196e1e9d7c16dd3b7d28dfa94b`,
    size `4569411`, notarization submission
    `dd1a71bc-1450-46ae-8ac1-f981d3150b11`, and Sparkle signature
    `pBk16roXWXtEMxKbR6HZAgD0vDSbojgSUzn2jS8xGZeGw2M9nGH1Y31RQZuGsA8/2SWxW9H/ENc90ESQCm8PCQ==`.
  - Release surfaces updated and verified: GitHub release `v1.1.17`, R2
    download, `https://sanehosts.com/appcast.xml`, Cloudflare Pages website,
    Homebrew tap commit `d2987c3`, and sane-email-automation commit `8b4bde9`.
  - Lemon Squeezy dashboard sync completed on the Mini: uploaded
    `SaneHosts-1.1.17.zip`, unpublished stale `SaneHosts-1.1.16.zip`, and
    verified `./scripts/SaneMaster.rb hosted_file_actions --json` reports
    SaneHosts `status: In sync` with one published file.
  - Post-sync `./scripts/SaneMaster.rb release_preflight` passed on the
    Mini-routed workspace with `99` tests. Remaining warnings only: App Store
    product marker absent, UserDefaults/migration changed, 6 pending customer
    emails, and evening release timing.

- 2026-06-21 Ponytail staged simplification pass completed without deleting
  customer proof or privileged hosts-write safety. Implemented stages:
  consolidated `QuickActionButton` / Pro lock UI without changing Basic vs Pro
  routing, removed unused local design helpers, removed the pass-through
  `DirectDistributionSupport.swift` mover wrapper, deleted stale generated docs
  and then restored `docs/appcast.xml` as required release metadata, removed backup icon PNGs, collapsed dormant
  App Store-only branches for the direct-download product, and deduped
  ProfileStore create/import append-sort persistence helpers. Net diff:
  `24 files changed, 239 insertions(+), 1979 deletions(-)` plus removed binary
  icon backups; Swift LOC dropped from `11726` to `10949`.
  Verification after each code stage: Mini `./scripts/SaneMaster.rb verify
  --timeout 900` passed `97` tests after Stage 1, Stage 2, Stage 3, and Stage 4.
  Final Mini runtime proof: `customer_ui_sweep --json` passed 11 actions with
  receipt timestamp `2026-06-21T05:31:11Z`, live log
  `outputs/live-logs/customer_ui_sanehosts_20260621T052946Z.log`, and visual
  smoke receipt `outputs/visual_smoke/visual_smoke_20260621-013043_38239`.
  Final release-mode resource soak from `/Applications/SaneHosts.app` passed
  240s / 33 samples with `avg_cpu: 0.0`, `peak_cpu: 0.0`,
  `peak_rss_mb: 152.859`, `peak_physical_footprint_mb: 78.0`, and no issues.
  Follow-up fixed the SaneProcess routed-receipt gap: routed workspaces now
  carry the canonical `.sane` receipt and `outputs/customer-ui/***` proof
  artifacts. Fresh Mini `customer_ui_sweep --json` passed with receipt
  `2026-06-21T07:42:44Z`, then routed `release_preflight` passed with `0`
  issues and expected warnings only (App Store product marker absent,
  uncommitted files, pending emails, evening release timing).

- 2026-06-04 MainView refactor/proof pass completed:
  - Split the former 2,457-line `MainView.swift` owner into focused SwiftUI
    files under `SaneHostsPackage/Sources/SaneHostsFeature/Views/`: `MainView.swift`
    (scene state/body), `MainView+Layout.swift`, `MainView+Actions.swift`,
    `MainViewComponents.swift`, `ProfileCreationSheets.swift`, `PresetViews.swift`,
    `FetchProgressOverlay.swift`, `RemoteImportSheet.swift`,
    `RemoteImportSheet+Catalog.swift`, `RemoteImportSheet+Import.swift`, and
    `MergeProfilesSheet.swift`. All split files are under 500 lines.
  - Updated source-policy tests so dark-mode readability, activation/deactivation,
    large-profile, and remote-import safety checks scan the new file boundaries.
  - Mini verification passed:
    `swift test --package-path SaneHostsPackage` and
    `./scripts/SaneMaster.rb verify --timeout 900` both passed; SaneMaster reported
    `97` tests passed. After the `1.1.16` / build `1116` release bump,
    Mini `./scripts/SaneMaster.rb verify --timeout 900` passed again with
    `97` tests.
  - Customer UI contract was refreshed after the source split and after the
    release metadata bump. Latest Mini `./scripts/SaneMaster.rb
    customer_ui_sweep --json` passed with 11 actions and receipt timestamp
    `2026-06-04T02:32:42Z`.
  - Release preflight for `1.1.16` passed with warnings only. Expected
    pre-publish warnings: uncommitted release-candidate files, UserDefaults
    migration notice, live appcast/Homebrew still at `1.1.15`, one open GitHub
    issue, pending email queue, and evening timing.
  - Mini runtime proof passed through `./scripts/SaneMaster.rb test_mode --no-logs`
    and `./scripts/SaneMaster.rb visual_smoke --app SaneHosts --output
    outputs/visual-audit-20260604 --json`.
  - Clean visual proof copied locally:
    `outputs/visual-audit-20260604/visual_smoke_20260603-222831_16745/app-see.png`.
    The isolated app capture shows the SaneHosts window rendering correctly with
    readable bright text, visible sidebar/detail/stats/entries, and no overlap.
    An earlier failed `screen.png` in
    `visual_smoke_20260603-222650_7365` is contaminated by a Codex
    window/notification and should not be used as visual proof.
  - Direct-download release `v1.1.16` shipped and deployed:
    `https://dist.sanehosts.com/updates/SaneHosts-1.1.16.zip`. Release tag
    `v1.1.16` points at `2f89e60`; release metadata commit `d87becc` is on
    `main`.
  - Release evidence: SaneMaster routed release from the MacBook Air to the Mini,
    passed `97` tests, archived/exported Developer ID signed app, notarized and
    stapled Apple submission `2c4a958d-620a-4304-b927-70972cb85f88`, uploaded R2
    ZIP SHA-256 `3aae3614d295e5df3989fd68f89fbf32cf3f96d25a0823dad3dce3ee63a391a5`,
    updated appcast/website/Homebrew/GitHub release, and verified the download.
  - Post-release preflight passed at `2026-06-03T23:08:34-04:00` with `0`
    issues and `4` warnings in `outputs/release_preflight_status.json`: upgrade
    path warning, one open GitHub issue, three pending emails, and evening timing.
    Live appcast/Homebrew/website download/email Worker signed download all report
    `1.1.16` / build `1116`.
  - Release tooling fix: Air-off-LAN releases were initially blocked because
    `release.sh` trusted SaneMaster's routed workspace context for cleanliness
    but still fell through to the old Mini-to-Air `.local` SSH reconcile query.
    `SaneProcess` branch `fix/hook-staleness-gates` commit `cb934c4` now lets
    routed releases pass reconcile from `.sanemaster/mini_route_context.json`.
  - Email Worker follow-up: the primary SaneHosts download mapping was pushed in
    `sane-email-automation` commit `7cff266`; bundle purchase mapping was also
    updated and tested in `c930f98`, then deployed to Cloudflare Worker version
    `f9b292a8-fde5-4b39-b7a6-025ecf1336dc`.

- 2026-06-01 `v1.1.15` direct-download release shipped and deployed:
  - Release URL: `https://dist.sanehosts.com/updates/SaneHosts-1.1.15.zip`.
  - Appcast: `https://sanehosts.com/appcast.xml`.
  - Release commits on `main`: `91a992b` enabled the direct 30-day Pro trial, `3b871cb` bumped version, and `802468d` synced release metadata. Tag `v1.1.15` was published.
  - Canonical Mini preflight passed with warnings only; release script reran `./scripts/SaneMaster.rb verify` and passed `97` tests.
  - Release script archived/exported signed app, notarized/stapled, uploaded R2 ZIP, updated appcast/website/Homebrew/email webhook, and strict post-release checks passed.
  - Expected warnings during preflight/release: migration-path notice, open GitHub/email queues, pre-publish appcast/Homebrew skew, README freshness warning, and evening timing warning. None blocked release.
- 2026-05-25 22:06 EDT Basic/Pro conversion patch verified:
  - SaneHosts now opts into the shared SaneUI 30-day Pro trial so new direct
    users see real Pro access during onboarding instead of being able to live
    indefinitely in a too-generous Basic path.
  - 2026-06-01 release prep bumped this patch to `1.1.15` / build `1115` and
    consolidated the duplicate `1.1.14` changelog entries.
  - Runtime proof on the Mini confirmed the staged app launched with mover
    prompts suppressed for test mode, keychain disabled for the fresh-user
    probe, and forced license check enabled. UserDefaults showed
    `sanehosts.pro_trial.started_at` plus the
    `sanehosts.pro_trial_started` event.
  - Verification: Mini `./scripts/SaneMaster.rb verify --timeout 1200` passed
    `97` tests. Mini visual smoke passed at
    `/Users/stephansmac/SaneApps/apps/SaneHosts/outputs/visual_smoke/visual_smoke_20260525-220458_32163`.
    Mini `customer_ui_sweep --json` passed with receipt generated
    `2026-05-26T02:06:25Z`.
  - Product caveat: the failed "Move to Applications" dialog was reproduced as
    a test-launcher problem and the tooling now suppresses/detects it during
    verification. A real customer install-move success pass should still be
    run before claiming the mover itself is fixed.

- 2026-05-25 20:05 EDT direct-download patch `v1.1.14` shipped and deployed:
  - Release commits on `main`: `b234f1a` fixed overlay/readability, large-profile
    runtime, import cancellation, DNS/activation error handling, and regression
    coverage; `4ff87eb` bumped version to `1.1.14`; `fa0b819` synced release
    metadata.
  - Canonical release artifact:
    `https://dist.sanehosts.com/updates/SaneHosts-1.1.14.zip`; appcast:
    `https://sanehosts.com/appcast.xml`; GitHub release: `v1.1.14`;
    Homebrew tap updated to `1.1.14`; website/email webhook updated to the same
    ZIP.
  - Verification before ship: Mini `./scripts/SaneMaster.rb verify --timeout 900`
    passed `96` tests; release script reran the same test suite; Mini
    `sane_test.rb SaneHosts --no-logs` built/launched the app; Mini
    `customer_ui_sweep --json` and strict `customer_ui_contract --strict-visual
    --json` passed with 11 covered customer actions.
  - Visual evidence inspected: normal completed-tutorial screenshot
    `outputs/local-visual/sanehosts-normal-app-see-20260525-191008.png` and
    first-run tutorial screenshot
    `outputs/local-visual/sanehosts-first-run-app-see-20260525-191125.png`; both
    were readable with no clipping/overlap and the first-run tooltip visible
    in-frame.
  - Runtime evidence: large profile startup no longer eagerly decodes 61 MB/25 MB
    JSON files. Final Mini samples stabilized around `0%` CPU, `~158 MB` RSS,
    and `~83 MB` physical footprint. Restricted `leaks` reported only tiny
    AppIntents/XPC allocations, with no growing app footprint observed.
  - Post-status dashboard cleanup: Lemon Squeezy hosted file was updated in the
    Mini Safari dashboard from `SaneHosts-1.1.13.zip` to `SaneHosts-1.1.14.zip`;
    the stale file was unpublished, and `./scripts/SaneMaster.rb
    hosted_file_actions --json` now reports `current_actions: []` with
    SaneHosts `status: In sync`.
  - Customer replies posted after user approval:
    `#4` comment `4538794202` was posted and the issue was closed as fixed in
    `1.1.14`; `#5` comment `4538794511` was posted and the issue remains open
    for reporter confirmation on `1.1.14`.
  - Tooling note: the canonical release script invoked an `nv` README sync despite
    the SaneApps no-NVIDIA/no-nv rule. It completed without changing README, but
    release tooling should be patched to use GPT/local tooling instead.

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

- Current direct-download release is `1.1.16` (build `1116`).
- SaneHosts remains direct-download only. The App Store lane is intentionally disabled for the current helper/daemon architecture.
- Pricing rollout source of truth for current customer-facing surfaces: `Basic = free`, `Pro = $14.99 once`, `direct download only`.
- Do not reintroduce App Store positioning in customer-facing copy unless the product is intentionally redesigned around an App-Store-safe architecture.
- Track pricing impact with `ruby ~/SaneApps/infra/SaneProcess/scripts/SaneMaster.rb sales --products`, `downloads --app SaneHosts --days 30`, and `events --app SaneHosts --days 30` before and after rollout windows.
- Use `CHANGELOG.md`, `ARCHITECTURE.md`, and git history for older release
  history and archived launch-ops notes. Active state above is current.

## Release Update - 2026-07-18

- Direct-channel SaneHosts `1.1.23` (build `1123`) is live. The public appcast
  contains a signed `SaneHosts-1.1.23.zip` enclosure and
  `<sparkle:criticalUpdate/>`. The release updated the website, Homebrew cask,
  and email webhook product mapping.
- The release fixes SaneApps Everything Bundle entitlement matching through the
  shared SaneUI revision `103803d`; SaneHosts now accepts the bundle while
  retaining mismatched single-app license rejection.
- Mini release proof: customer UI contract `11` actions, behavioral migration
  proof, and release preflight verify evidence `115` tests passed. Clean Mini
  visual proof: `/Users/sj/Desktop/Screenshots/codex-shot-2026-07-18_06-29-08.png`.
- The direct-channel release is not fully complete until the Lemon Squeezy
  hosted variant is manually replaced with the already-public
  `SaneHosts-1.1.23.zip` from `https://dist.sanehosts.com/updates/` and
  post-release checks are rerun. The dashboard product is `794910`, variant
  `1253740`; current hosted file is still `1.1.22`.
- Product roadmap issue: `https://github.com/sane-apps/SaneHosts/issues/6`
  tracks helper-enforced Parent Lock, update migration, and acceptance tests.
- Customer feedback about large blocklist activation shipped in `1.1.22`; a
  delivery-confirmed support response was sent, but the thread remains pending
  without a subsequent customer confirmation.

## Launch Ops - 2026-06-23

- Cross-product launch ops reran canonical Mini `./scripts/SaneMaster.rb launch_readiness --json` from the SaneHosts repo. It stayed red.
- Active launch blockers are unchanged: the 30-second privacy-switch video still needs human visual approval plus a hosted/public URL, the staged website video still is not publicly deployed, and the Product Hunt maker comment/day-of checklist still needs exact approval.
- Fresh proof state: `release_preflight` still passes but is stale at 19.43 days with 4 warnings, and the shared validation receipt [`/Users/sj/SaneApps/infra/SaneProcess/outputs/validation/2026-06-23.json`](/Users/sj/SaneApps/infra/SaneProcess/outputs/validation/2026-06-23.json) is still `NOT READY FOR RELEASE` with stale SaneHosts customer-UI proof. No package/submission/scheduling/public-post action ran today.
