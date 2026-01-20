# Privacy Policy

**Last updated: January 18, 2025**

SaneHosts is designed with privacy as a core principle. This document explains how the app handles your data.

## Our Philosophy

**Your data stays on your device.** Period.

## Data Collection

### What We DON'T Collect
- No analytics or telemetry
- No crash reports sent externally
- No usage statistics
- No personal information
- No network requests except when YOU initiate remote import

### What Stays Local
- **Profiles** - Stored in `~/Library/Application Support/SaneHosts/`
- **Preferences** - Stored in macOS defaults system
- **Hosts modifications** - Written directly to `/etc/hosts`

## Permissions Used

### File System Access
- **Application Support** - To store your profiles
- **/etc/hosts** - To apply hosts file changes (requires admin authentication)

### Network Access
- **Optional** - Only when you import hosts from a remote URL
- You control when this happens
- No automatic/background network requests

### System Services
- **ServiceManagement** - For launch at login feature (optional)
- **DNS Flushing** - Runs `dscacheutil -flushcache` locally

## Third-Party Services

SaneHosts uses no third-party services, SDKs, or analytics.

## Auto-Updates

When enabled, SaneHosts checks for updates via Sparkle framework:
- Connects to `sanehosts.com/appcast.xml`
- Only checks for version information
- No personal data transmitted

## Remote Hosts Import

When you choose to import hosts from a URL:
- The app fetches the URL you specify
- Content is parsed locally
- No data is sent anywhere
- The source URL is not logged or tracked

## Data Retention

All data is stored locally and persists until you:
- Delete profiles through the app
- Uninstall the app
- Manually delete Application Support files

## Your Rights

You have full control:
- View all stored data in Application Support folder
- Delete any or all profiles
- Disable all optional features
- Uninstall completely with no traces (see below)

## Complete Uninstall

To remove all SaneHosts data:
```bash
# Remove application
rm -rf /Applications/SaneHosts.app

# Remove preferences
defaults delete com.sanehosts.app

# Remove application data
rm -rf ~/Library/Application\ Support/SaneHosts
rm -rf ~/Library/Caches/com.sanehosts.app
```

## Contact

Questions about privacy? Open an issue on [GitHub](https://github.com/sane-apps/SaneHosts/issues).

## Changes

Any changes to this policy will be documented in the CHANGELOG and noted in release notes.
