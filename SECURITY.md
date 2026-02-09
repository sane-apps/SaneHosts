# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.x.x   | :white_check_mark: |

## Security Model

### App Sandbox
SaneHosts runs **without** App Sandbox because it must write directly to `/etc/hosts` (a system file outside any sandbox container). To compensate:
- Hardened runtime is enabled
- Code is signed with Developer ID and notarized by Apple
- No unnecessary entitlements beyond what is required

### Privileged Operations
Modifying `/etc/hosts` requires elevated privileges:
- Admin authentication is requested via macOS system dialog
- Uses `do shell script with administrator privileges` (AppleScript)
- Password is never stored or logged
- Each modification requires re-authentication

### Code Signing
- Signed with Developer ID: Mr. Sane (M78L6FXD48)
- Notarized by Apple
- Hardened runtime enabled

### Data Security
- No sensitive data stored
- Profiles contain only hosts mappings
- No credentials, tokens, or personal data

## Reporting a Vulnerability

If you discover a security vulnerability, please:

1. **DO NOT** open a public issue
2. Email security concerns to: hi@saneapps.com
3. Or use GitHub's private vulnerability reporting

### What to Include
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

### Response Timeline
- **Initial Response**: Within 48 hours
- **Assessment**: Within 1 week
- **Fix Timeline**: Depends on severity
  - Critical: Patch release within 48 hours
  - High: Patch release within 1 week
  - Medium: Next regular release
  - Low: Backlog for future release

### Recognition
Security researchers who report valid vulnerabilities will be:
- Credited in release notes (unless they prefer anonymity)
- Added to SECURITY.md acknowledgments

## Security Best Practices for Users

1. **Download from official sources only**
   - sanehosts.com

2. **Verify code signature**
   ```bash
   codesign -dv --verbose=4 /Applications/SaneHosts.app
   # Should show: Developer ID Application: Mr. Sane (M78L6FXD48)
   ```

3. **Keep the app updated**
   - Enable auto-update checks
   - Security fixes are prioritized

4. **Review hosts before applying**
   - Especially for remote imports
   - Malicious hosts can redirect traffic

## Known Security Considerations

### Hosts File Risks
The hosts file can redirect any domain. A malicious hosts entry could:
- Redirect banking sites to phishing pages
- Block security update servers
- Redirect any website

**Mitigations**:
- Only import hosts from trusted sources
- Review entries before activating profiles
- Use built-in templates from vetted sources

### Remote Import Risks
When importing from URLs:
- The content is fetched without verification
- HTTPS is recommended but not enforced
- Content is parsed but not validated for malice

**Mitigations**:
- Only import from trusted URLs
- Review imported entries before activation
- Prefer built-in templates

## Acknowledgments

Thanks to the following for responsible disclosure:
- (No reports yet)
