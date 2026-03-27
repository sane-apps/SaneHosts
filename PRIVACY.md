# Privacy Policy

> [README](README.md) · [ARCHITECTURE](ARCHITECTURE.md) · [DEVELOPMENT](DEVELOPMENT.md) · [PRIVACY](PRIVACY.md) · [SECURITY](SECURITY.md)

**Last updated: March 26, 2026**

SaneHosts is built to keep your hosts data on your Mac. Here is the plain-English version: your profiles and hosts entries stay local, and the app only talks to the network in a few specific cases.

## Summary

**Your hosts entries and profiles stay on your Mac.** SaneHosts does not upload that data to SaneApps servers.

The app may send a few simple anonymous counts, such as whether it opened in Basic or Pro, so we can understand product usage at a high level. Those counts do not include your hosts entries, profile contents, or personal files.

## What We Do Not Collect

SaneHosts does not collect:

- Your hosts entries or profile contents on SaneApps servers
- Personal files from your Mac
- Crash reports
- Your administrator password

## What Stays On Your Mac

SaneHosts stores the following locally on your Mac:

- **Profiles** in `~/Library/Application Support/SaneHosts/Profiles/`
- **Backups** in `~/Library/Application Support/SaneHosts/Backups/`
- **Blocklist cache** in `~/Library/Application Support/SaneHosts/BlocklistCache/`
- **Preferences** in standard macOS defaults
- **Hosts changes** written directly to `/etc/hosts`

In normal use, this stays on your Mac unless you choose a feature that fetches something from the internet, like importing a remote blocklist.

## When SaneHosts Uses The Network

SaneHosts uses the network only when:

- You choose to import a blocklist from a URL
- It checks for app updates, if update checks are enabled
- It sends a few simple anonymous app counts, such as Basic vs Pro launches

Your hosts entries and profile contents are not sent to SaneApps.

## Third-Party Services

SaneHosts uses a small number of outside services:

- **Sparkle** to check for app updates
- **SaneApps distribution service** to receive simple anonymous app counts
- **Cloudflare Web Analytics** on public website pages
- **Google Fonts** on some public website pages

Those website services apply to `sanehosts.com` pages, not to your hosts entries or profile contents inside the app.

## Remote Imports

If you import a hosts file from a URL:

- SaneHosts fetches the URL you chose
- The content is processed on your Mac
- The resulting entries stay local unless you export or share them yourself

## Your Control

You can:

- View your local SaneHosts data in Application Support
- Delete profiles and backups
- Turn off update checks
- Uninstall the app and remove its local data

## Contact

Questions about privacy? Open an issue on [GitHub](https://github.com/sane-apps/SaneHosts/issues).
