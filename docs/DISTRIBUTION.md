# SaneHosts Distribution Guide

Complete guide for releasing SaneHosts to the public.

## CRITICAL: Existing Keys & Credentials

**Sparkle EdDSA Key** (ALREADY EXISTS in sj's keychain):
- **Public Key**: `QwXgCpqQfcdZJ6BIzLRrBmn2D7cwkNbaniuIkm/DJyQ=`
- **Location**: macOS Keychain → "Private key for signing Sparkle updates"
- **Configured in**: `Config/Shared.xcconfig` → `INFOPLIST_KEY_SUPublicEDKey`

**Apple Developer Credentials** (in system keychain):
- **Keychain Profile**: `notarytool`
- **Key ID**: `7LMFF3A258`
- **Team ID**: `M78L6FXD48`

**DO NOT regenerate keys** - use the existing ones above.

---

## Prerequisites

- [ ] Xcode 16+ installed
- [ ] Apple Developer Program membership
- [ ] Developer ID Application certificate
- [ ] Notarization credentials in keychain (`notarytool` profile)
- [ ] Domain purchased (sanehosts.com)

## First-Time Setup

### 1. Generate Sparkle Signing Keys

```bash
./scripts/setup_sparkle_keys.sh
```

This will:
- Generate EdDSA key pair in `keys/` directory
- Update `Config/Shared.xcconfig` with public key
- Add `keys/` to `.gitignore`

**IMPORTANT:** Back up `keys/sparkle_private_key` securely. If lost, you cannot sign updates.

### 2. Verify Code Signing

```bash
# Check Developer ID certificate
security find-identity -v -p codesigning | grep "Developer ID"

# Verify notarization credentials
xcrun notarytool history --keychain-profile "notarytool"
```

## Release Process

### Step 1: Update Version

Edit `Config/Shared.xcconfig`:
```
MARKETING_VERSION = 1.0.1
CURRENT_PROJECT_VERSION = 2
```

### Step 2: Update Changelog

Edit `CHANGELOG.md` with release notes.

### Step 3: Build Release

```bash
./scripts/build_release.sh
```

This will:
1. Clean and archive the project
2. Export with Developer ID signing
3. Create DMG
4. Notarize with Apple
5. Staple notarization ticket
6. Output to `releases/SaneHosts-X.X.dmg`

### Step 4: Generate Appcast

```bash
./scripts/generate_appcast.sh
```

This creates `docs/appcast.xml` for Sparkle updates.

### Step 5: Create GitHub Release

```bash
VERSION=$(grep "MARKETING_VERSION" Config/Shared.xcconfig | cut -d'=' -f2 | tr -d ' ')
DMG="releases/SaneHosts-${VERSION}.dmg"

# Create release
gh release create "v${VERSION}" "$DMG" \
  --title "SaneHosts ${VERSION}" \
  --notes-file CHANGELOG.md
```

### Step 6: Deploy Website

Upload to sanehosts.com:
- `website/index.html` → `/index.html`
- `website/privacy.html` → `/privacy.html`
- `docs/appcast.xml` → `/appcast.xml`
- App screenshot → `/screenshot.png`

## File Locations

| File | Purpose |
|------|---------|
| `scripts/build_release.sh` | Build, sign, notarize DMG |
| `scripts/generate_appcast.sh` | Generate Sparkle feed |
| `scripts/setup_sparkle_keys.sh` | One-time key generation |
| `keys/sparkle_private_key` | **SECRET** - EdDSA private key |
| `keys/sparkle_public_key` | EdDSA public key |
| `releases/` | Built DMGs and checksums |
| `docs/appcast.xml` | Sparkle update feed |
| `website/` | Website HTML files |

## Checklist for Each Release

```
[ ] Version bumped in Shared.xcconfig
[ ] CHANGELOG.md updated
[ ] ./scripts/build_release.sh completed
[ ] ./scripts/generate_appcast.sh completed
[ ] GitHub release created with DMG
[ ] appcast.xml deployed to sanehosts.com
[ ] Tested download and update flow
```

## Troubleshooting

### Notarization Failed
```bash
# Check submission status
xcrun notarytool log <submission-id> --keychain-profile "notarytool"
```

Common issues:
- Missing hardened runtime
- Unsigned nested code
- Invalid entitlements

### Sparkle Update Not Working
1. Verify `SUPublicEDKey` in Info.plist matches your public key
2. Verify appcast.xml is accessible at the feed URL
3. Check Console.app for Sparkle errors

### Code Signing Issues
```bash
# Verify signature
codesign -dvvv /path/to/SaneHosts.app
spctl --assess --type execute -vvv /path/to/SaneHosts.app
```

## Security Notes

1. **Never commit** `keys/sparkle_private_key`
2. **Never share** your Developer ID private key
3. **Always notarize** before distribution
4. **Keep backups** of signing keys

## Support

- GitHub Issues: https://github.com/sane-apps/SaneHosts/issues
- Email: support@sanehosts.com
