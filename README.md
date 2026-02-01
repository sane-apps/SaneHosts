# SaneHosts

> Modern hosts file manager for macOS

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-brightgreen)](https://www.apple.com/macos)
[![Swift 6.1](https://img.shields.io/badge/Swift-6.1-orange.svg)](https://swift.org)

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

Download from [sanehosts.com](https://sanehosts.com).

Or build from source (see [Contributing](#contributing)).

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

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting a pull request.

## Support

- [Report a Bug](https://github.com/sane-apps/SaneHosts/issues/new?template=bug_report.md)
- [Request a Feature](https://github.com/sane-apps/SaneHosts/issues/new?template=feature_request.md)

## License

GPL v3 — see [LICENSE](LICENSE) for details.

---

Made with care by [Mr. Sane](https://github.com/sane-apps)
