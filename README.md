# SaneHosts

> Modern hosts file manager for macOS

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-brightgreen)](https://www.apple.com/macos)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)

SaneHosts is a native macOS app that makes managing your `/etc/hosts` file simple and intuitive. Create profiles for different scenarios, use built-in templates, and switch between configurations with a click.

## Features

- **Profile Management** - Create and manage multiple hosts configurations with color tagging
- **50+ Curated Blocklists** - Import from Steven Black, Hagezi, AdGuard, and more
- **Built-in Templates** - Ad blocking, privacy, social media blocking, development
- **Remote Import** - Import hosts from any URL, supports domain-only format
- **Merge Profiles** - Combine multiple profiles with automatic deduplication
- **Automatic DNS Flush** - DNS cache cleared when activating profiles
- **Menu Bar Access** - Quick profile switching from the menu bar
- **Touch ID Support** - Authenticate with biometrics when available
- **Crash Resilient** - Automatic backups, corrupted profiles recovered automatically
- **Native macOS** - Built with SwiftUI, follows system conventions
- **Privacy-First** - All data stored locally, no analytics, no cloud

## Installation

Download from [sanehosts.com](https://sanehosts.com).

Or build from source (see [Contributing](#contributing)).

## Requirements

- macOS 14.0 (Sonoma) or later
- Administrator password (for hosts file modifications)

## How It Works

1. **Create a Profile** - Define hosts mappings for a specific use case
2. **Use Templates** - Start with built-in templates or import from URLs
3. **Activate** - Apply the profile to your `/etc/hosts` file
4. **Switch** - Change profiles as needed, DNS cache is flushed automatically

## Screenshots

See [sanehosts.com](https://sanehosts.com) for screenshots and demo.

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘N` | New Profile |
| `⌘I` | Import Blocklist |
| `⌘D` | Duplicate Profile |
| `⌘M` | Merge Selected |
| `⌘E` | Export Profile |
| `⌘⇧A` | Activate Profile |
| `⌘⇧D` | Deactivate All |
| `⌘⌫` | Delete Profile |

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

MIT License - see [LICENSE](LICENSE) for details.

---

Made with care by [Mr. Sane](https://github.com/sane-apps)
