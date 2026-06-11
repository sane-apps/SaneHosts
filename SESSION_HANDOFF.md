# Session Handoff — SaneHosts

**Last updated:** 2026-06-04

## Current State

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
