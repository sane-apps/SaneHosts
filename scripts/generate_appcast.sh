#!/bin/bash
set -e

# =============================================================================
# SaneHosts Appcast Generator
# Creates Sparkle appcast.xml for automatic updates
# =============================================================================

# Configuration
APP_NAME="SaneHosts"
DOWNLOAD_BASE_URL="https://github.com/mrsane/SaneHosts/releases/download"
WEBSITE_URL="https://sanehosts.com"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RELEASES_DIR="$PROJECT_DIR/releases"
KEYS_DIR="$PROJECT_DIR/keys"
APPCAST_FILE="$PROJECT_DIR/docs/appcast.xml"

# Check for Sparkle tools
SPARKLE_BIN=""
if [ -d "/Users/sj/Library/Developer/Xcode/DerivedData" ]; then
    SPARKLE_BIN=$(find /Users/sj/Library/Developer/Xcode/DerivedData -name "sign_update" -type f 2>/dev/null | head -1)
fi

if [ -z "$SPARKLE_BIN" ]; then
    # Try to find in build products
    SPARKLE_BIN=$(find "$PROJECT_DIR" -name "sign_update" -type f 2>/dev/null | head -1)
fi

# Get version from xcconfig
VERSION=$(grep "MARKETING_VERSION" "$PROJECT_DIR/Config/Shared.xcconfig" | cut -d'=' -f2 | tr -d ' ')
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="$RELEASES_DIR/$DMG_NAME"

# Check DMG exists
if [ ! -f "$DMG_PATH" ]; then
    echo "ERROR: DMG not found at $DMG_PATH"
    echo "Run ./scripts/build_release.sh first"
    exit 1
fi

# Get file info
FILE_SIZE=$(stat -f%z "$DMG_PATH")
SHA256=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")
DOWNLOAD_URL="${DOWNLOAD_BASE_URL}/v${VERSION}/${DMG_NAME}"

# EdDSA signature (if keys exist)
EDDSA_SIGNATURE=""
if [ -f "$KEYS_DIR/sparkle_private_key" ] && [ -n "$SPARKLE_BIN" ]; then
    echo ">>> Signing with EdDSA..."
    EDDSA_SIGNATURE=$("$SPARKLE_BIN" "$DMG_PATH" -f "$KEYS_DIR/sparkle_private_key" 2>/dev/null || echo "")
fi

# Generate appcast
echo ">>> Generating appcast.xml..."
mkdir -p "$(dirname "$APPCAST_FILE")"

cat > "$APPCAST_FILE" << EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>${APP_NAME} Updates</title>
    <link>${WEBSITE_URL}/appcast.xml</link>
    <description>Most recent changes with links to updates.</description>
    <language>en</language>

    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
        <h2>What's New in ${APP_NAME} ${VERSION}</h2>
        <ul>
          <li>Initial release</li>
          <li>Profile-based hosts file management</li>
          <li>Import blocklists from popular sources</li>
          <li>Menu bar quick access</li>
          <li>Automatic DNS cache flush</li>
        </ul>
      ]]></description>
      <enclosure
        url="${DOWNLOAD_URL}"
        length="${FILE_SIZE}"
        type="application/octet-stream"
        sparkle:edSignature="${EDDSA_SIGNATURE}"
      />
    </item>

  </channel>
</rss>
EOF

echo ""
echo "=============================================="
echo "APPCAST GENERATED!"
echo "=============================================="
echo ""
echo "File: $APPCAST_FILE"
echo ""
echo "Version: $VERSION"
echo "Size: $FILE_SIZE bytes"
echo "SHA256: $SHA256"
echo "Download URL: $DOWNLOAD_URL"
if [ -n "$EDDSA_SIGNATURE" ]; then
    echo "EdDSA Signature: ${EDDSA_SIGNATURE:0:20}..."
else
    echo "EdDSA Signature: NOT SET (generate keys first)"
fi
echo ""
echo "Next steps:"
echo "1. Upload appcast.xml to sanehosts.com/appcast.xml"
echo "2. Upload DMG to GitHub release v${VERSION}"
echo ""
