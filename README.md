# SaneHosts

> Modern hosts file manager for macOS

[![GitHub stars](https://img.shields.io/github/stars/sane-apps/SaneHosts?style=flat-square)](https://github.com/sane-apps/SaneHosts/stargazers)
[![License: PolyForm Shield](https://img.shields.io/badge/License-PolyForm%20Shield-blue.svg)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-brightgreen)](https://www.apple.com/macos)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)

> **⭐ Star this repo if it's useful!** · **[💰 Buy for $6.99](https://sanehosts.com)** · Keeps development alive

SaneHosts is a native macOS app that makes managing your `/etc/hosts` file simple and intuitive. Choose a protection level, activate it, done. No Terminal. No commands. If something breaks, just deactivate.

## Features

### Protection Levels
Choose from 5 curated protection levels - each bundles the right blocklists for your needs:

| Level | What It Blocks |
|-------|---------------|
| **Essentials** | Ads, trackers, malware - the basics everyone needs |
| **Balanced** | Essentials + phishing, fraud, aggressive tracking |
| **Strict** | Balanced + social media trackers, native telemetry |
| **Aggressive** | Strict + gambling, piracy, adult content |
| **Kitchen Sink** | Everything available - maximum blocking |

### Core Features
- **Profile Management** - Create and manage multiple hosts configurations with color tagging
- **200+ Curated Blocklists** - Import from Steven Black, Hagezi, AdGuard, OISD, and 10+ categories. SaneHosts is an **officially listed tool** in the upstream StevenBlack/hosts repository.
- **Guided Setup** - Coach mark tutorial walks you through activation on first launch
- **Remote Import** - Import hosts from any URL or paste custom blocklist URLs
- **Merge Profiles** - Combine multiple profiles with automatic deduplication
- **Automatic DNS Flush** - DNS cache cleared when activating profiles
- **Menu Bar Access** - Quick profile switching from the menu bar
- **Crash Resilient** - Automatic backups (3 per profile), corrupted profiles recovered automatically
- **Native macOS** - Built with SwiftUI, follows system conventions
- **Privacy-First** - All data stored locally, no analytics, no cloud
- **Export Profiles** - Save profiles as standard `.hosts` format files
- **Drag to Reorder** - Organize profiles by dragging in the sidebar
- **Search & Filter** - Find entries across large profiles (handles 100K+ entries)
- **URL Health Checks** - Visual indicators show blocklist source availability

## Installation

**[Download from sanehosts.com](https://sanehosts.com)** — Signed, notarized, ready to use.

> *I wanted to make it $5, but processing fees and taxes were... insane. — Mr. Sane*

**Building from source?** Consider [buying the app](https://sanehosts.com) to support continued development.

## Requirements

- macOS 14.0 (Sonoma) or later
- Administrator password (for hosts file modifications)

## How It Works

1. **Choose a Protection Level** - Pick from Essentials to Kitchen Sink, or create a custom profile
2. **Import Blocklists** - Use curated presets or import from 200+ sources
3. **Activate** - Apply the profile to your `/etc/hosts` file (password required once)
4. **Switch** - Change profiles as needed, DNS cache is flushed automatically

## Screenshots

See [sanehosts.com](https://sanehosts.com) for screenshots and demo.

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘N` | New Profile |
| `⌘I` | Import Blocklist |
| `⌘A` | Select All Profiles |
| `⌘D` | Duplicate Profile |
| `⌘M` | Merge Selected Profiles |
| `⌘E` | Export Profile |
| `⌘⇧A` | Activate Profile |
| `⌘⇧D` | Deactivate All |
| `⌘⌫` | Delete Profile |
| `Delete` | Delete Selected (in list) |

## Privacy

SaneHosts is designed with privacy in mind:
- All data stored locally in `~/Library/Application Support/SaneHosts/`
- No analytics, telemetry, or crash reporting
- Network access only when YOU import from a remote URL

See [PRIVACY.md](PRIVACY.md) for details.

## Security

- Hosts file modifications require admin authentication
- Code signed and notarized by Apple
- Hardened runtime enabled

See [SECURITY.md](SECURITY.md) for details.

## Contributing

Before opening a PR:
1. **[⭐ Star the repo](https://github.com/sane-apps/SaneHosts)** (if you haven't already)
2. Read [CONTRIBUTING.md](CONTRIBUTING.md)
3. Open an issue first to discuss major changes

## Support

**[⭐ Star the repo](https://github.com/sane-apps/SaneHosts)** if SaneHosts helps you. Stars help others discover quality software.

**Cloning without starring?** For real bro? Gimme that star!

- 🐛 [Report a Bug](https://github.com/sane-apps/SaneHosts/issues/new?template=bug_report.md)
- 💡 [Request a Feature](https://github.com/sane-apps/SaneHosts/issues/new?template=feature_request.md)

## License

[PolyForm Shield 1.0.0](https://polyformproject.org/licenses/shield/1.0.0) — free for any use except building a competing product. See [LICENSE](LICENSE) for details.

---

Made with care by [Mr. Sane](https://github.com/sane-apps)

<!-- SANEAPPS_AI_CONTRIB_START -->
### Become a Contributor (Even if You Don't Code)

Are you tired of waiting on the dev to get around to fixing your problem?  
Do you have a great idea that could help everyone in the community, but think you can't do anything about it because you're not a coder?

Good news: you actually can.

Copy and paste this into Claude or Codex, then describe your bug or idea:

```text
I want to contribute to this repo, but I'm not a coder.

Repository:
https://github.com/sane-apps/SaneHosts

Bug or idea:
[Describe your bug or idea here in plain English]

Please do this for me:
1) Understand and reproduce the issue (or understand the feature request).
2) Make the smallest safe fix.
3) Open a pull request to https://github.com/sane-apps/SaneHosts
4) Give me the pull request link.
5) Open a GitHub issue in https://github.com/sane-apps/SaneHosts/issues that includes:
   - the pull request link
   - a short summary of what changed and why
6) Also give me the exact issue link.

Important:
- Keep it focused on this one issue/idea.
- Do not make unrelated changes.
```

If needed, you can also just email the pull request link to hi@saneapps.com.

I review and test every pull request before merge.

If your PR is merged, I will publicly give you credit, and you'll have the satisfaction of knowing you helped ship a fix for everyone.
<!-- SANEAPPS_AI_CONTRIB_END -->
