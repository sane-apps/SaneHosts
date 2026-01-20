# Changelog

All notable changes to SaneHosts will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2025-01-18

### Added
- Profile-based hosts file management
- Built-in templates (ad blocking, privacy, social media, development)
- Remote hosts file import from URLs
- Automatic DNS cache flushing
- Menu bar quick access
- Launch at login support
- Glass morphism UI matching SaneApps design system
- Full /etc/hosts parsing and writing via privileged helper
- Profile activation/deactivation with system integration

### Security
- Hosts file modifications require admin authentication
- No network access except for remote hosts import
- All data stored locally in Application Support

[Unreleased]: https://github.com/sane-apps/SaneHosts/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/sane-apps/SaneHosts/releases/tag/v1.0.0
