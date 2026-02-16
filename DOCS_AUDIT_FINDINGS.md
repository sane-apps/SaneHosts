# SaneHosts Documentation Audit Findings

**Date:** 2026-02-16
**Perspectives:** 15 (engineer, designer, marketer, user, QA, hygiene, security, freshness, completeness, ops, brand, consistency, website, marketing-framework, CX-parity)
**Models:** Mistral 675B (batch 1), DeepSeek (batch 2)

---

## Executive Summary

| # | Perspective | Score | Critical | Warnings |
|---|-------------|-------|----------|----------|
| 1 | Engineer | 8.5/10 | 0 | 10 |
| 2 | Designer | 8.5/10 | 7 | 8 |
| 3 | Marketer | 7.5/10 | 5 | 5 |
| 4 | User Advocate | 7/10 | 5 | 10 |
| 5 | QA | 6.5/10 | 7 | 12 |
| 6 | Hygiene | 8.5/10 | 0 | 3 |
| 7 | Security | 7.5/10 | 4 | 6 |
| 8 | Freshness | 8/10 | 3 | 4 |
| 9 | Completeness | 6/10 | 2 | 5 |
| 10 | Ops | 7/10 | 3 | 5 |
| 11 | Brand | 4/10 | 3 | 5 |
| 12 | Consistency | 6/10 | 4 | 5 |
| 13 | Website Standards | 4/6 | 2 | 2 |
| 14 | Marketing Framework | 5/5 | 0 | 2 |
| 15 | CX Parity | 4/10 | 3 | 5 |

**Overall: 6.8/10 — Good foundation, closer to PH-ready after resolving false positives (privacy page exists, version fixed)**

---

## CRITICAL ISSUES (Deduplicated, Priority Order)

### 1. ~~No Privacy Policy Page~~ [RESOLVED 2026-02-16]
**Flagged by:** Engineer, Marketer, User, QA, Freshness, Website
**Resolution:** FALSE POSITIVE — `website/privacy.html` already exists with comprehensive content (data collection, local storage, network access, system access, third-party services, open source, uninstall instructions). `guides.html` also exists.

### 2. ~~Version Number Mismatch~~ [RESOLVED 2026-02-16]
**Flagged by:** Designer, Freshness, QA, Consistency
**Resolution:** Fixed JSON-LD `softwareVersion` from "1.0.9" to "1.0.8" in `website/index.html` to match `Shared.xcconfig` and Sparkle appcast.

### 3. No Demo Video/GIF
**Flagged by:** ALL perspectives
**Impact:** PH listings with video get 2-3x more upvotes; users can't see the UX before downloading
**Fix:** Record 30-60s screen capture: Install → Pick Essentials → Activate → Protected

### 4. App Store Entitlements Are Non-Viable
**Flagged by:** QA, Ops, Consistency
**Impact:** Current entitlements (sandbox + apple-events) CANNOT write /etc/hosts. This is architecturally impossible.
**Fix:** Either (a) implement NEDNSSettingsManager for App Store version, or (b) remove App Store claims and focus on direct download

### 5. CX Parity Gaps (Score: 4/10)
**Flagged by:** CX, User, QA
**Impact:** No in-app bug reporting, no DiagnosticsService, no runtime permission detection for DNS flush failures
**Fix:** Add FeedbackView, DiagnosticsService, and surface DNS flush failures to user

### 6. Brand Compliance Low (Score: 4/10)
**Flagged by:** Brand
**Impact:** Not using SaneUI shared package, possible gray-on-dark text violations
**Fix:** Audit SwiftUI views for .secondary/.gray usage, integrate SaneUI colors

### 7. Security: No Blocklist Signature Verification
**Flagged by:** Security
**Impact:** Users import from arbitrary URLs with no integrity check; compromised lists could inject entries
**Fix:** Add HTTPS enforcement + optional checksum verification for curated lists

### 8. First-Launch Friction
**Flagged by:** Marketer, User, Designer
**Impact:** Website promises "Pick. Click. Protected." but app requires profile setup + admin password before showing value
**Fix:** Essentials profile is already auto-created on first launch (confirmed in code). Ensure coach marks align with actual UI.

---

## WARNINGS (Key Items)

| Issue | Source | Fix |
|-------|--------|-----|
| Missing changelog on website | Multiple | Add changelog.html |
| Missing FAQ page | User, QA | Add faq.html (common questions) |
| Touch ID buried in Settings | Marketer, Designer | Surface in toolbar/onboarding |
| No "What Now?" after activation | User, Marketer | Show success confirmation + test guidance |
| Terminology drift: "Presets" vs "Protection Levels" | Hygiene | Standardize to "Protection Levels" |
| Cross-sell links may 404 | User | Verify all sister app URLs |
| No competitor comparison documented | Marketer, User | Add comparison table (vs Gas Mask, AdGuard, NextDNS) |
| Missing trust badges per brand standard | Website | Add "No spying · No subscription · Actively maintained" |
| Broken keyboard shortcuts when no profile active | User, QA | Handle gracefully |
| Marketing framework is 5/5 but in-app copy is weaker | Marketing | Align in-app labels with website messaging |

---

## PASSED (Strengths)

- Marketing framework: 5/5 — Threat → Barrier → Solution → Promise is strong
- Website copy: "Your Mac Is Talking Behind Your Back" — compelling hook
- Error handling: 0 force unwraps, proper do/catch throughout
- Concurrency: @MainActor properly used on stores
- Open source credibility: StevenBlack/hosts listing, GPL v3
- One-time pricing: Clear, no subscription
- Profile backup/recovery: Crash-resilient with auto-recovery
- Documentation hygiene: 8.5/10, 5-doc standard followed
- Sparkle updates: Properly configured with shared key

---

## RAW PERSPECTIVE OUTPUTS

Full outputs preserved at `/tmp/docsaudit_*.txt` (15 files, ~150KB total).
