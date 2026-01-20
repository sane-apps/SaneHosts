#!/bin/bash
set -e

# =============================================================================
# SaneHosts Release Build Script
# Creates a signed, notarized DMG for distribution
# =============================================================================

# Configuration
APP_NAME="SaneHosts"
BUNDLE_ID="com.mrsane.SaneHosts"
TEAM_ID="M78L6FXD48"
KEYCHAIN_PROFILE="notarytool"
DEVELOPER_ID="Developer ID Application: Stephan Joseph (${TEAM_ID})"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WORKSPACE="$PROJECT_DIR/SaneHosts.xcworkspace"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/${APP_NAME}.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
DMG_DIR="$BUILD_DIR/dmg"
OUTPUT_DIR="$PROJECT_DIR/releases"

# Get version from xcconfig
VERSION=$(grep "MARKETING_VERSION" "$PROJECT_DIR/Config/Shared.xcconfig" | cut -d'=' -f2 | tr -d ' ')
BUILD_NUMBER=$(grep "CURRENT_PROJECT_VERSION" "$PROJECT_DIR/Config/Shared.xcconfig" | cut -d'=' -f2 | tr -d ' ')
DMG_NAME="${APP_NAME}-${VERSION}.dmg"

echo "=============================================="
echo "Building ${APP_NAME} v${VERSION} (${BUILD_NUMBER})"
echo "=============================================="

# Clean previous builds
echo ">>> Cleaning previous builds..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$EXPORT_PATH" "$DMG_DIR" "$OUTPUT_DIR"

# Archive
echo ">>> Creating archive..."
xcodebuild archive \
    -workspace "$WORKSPACE" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_IDENTITY="$DEVELOPER_ID" \
    CODE_SIGN_STYLE="Manual" \
    | xcpretty || xcodebuild archive \
    -workspace "$WORKSPACE" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_IDENTITY="$DEVELOPER_ID" \
    CODE_SIGN_STYLE="Manual"

# Create export options plist
echo ">>> Creating export options..."
cat > "$BUILD_DIR/ExportOptions.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>
EOF

# Export
echo ">>> Exporting app..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist"

# Verify code signature (basic check before notarization)
echo ">>> Verifying code signature..."
codesign --verify --deep --strict --verbose=2 "$EXPORT_PATH/${APP_NAME}.app"
# Note: spctl --assess will fail until after notarization, so we skip it here

# Create DMG
echo ">>> Creating DMG..."
cp -R "$EXPORT_PATH/${APP_NAME}.app" "$DMG_DIR/"

# Create DMG with hdiutil
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDZO \
    "$BUILD_DIR/${DMG_NAME}"

# Sign the DMG
echo ">>> Signing DMG..."
codesign --force --sign "$DEVELOPER_ID" "$BUILD_DIR/${DMG_NAME}"

# Notarize
echo ">>> Submitting for notarization..."
xcrun notarytool submit "$BUILD_DIR/${DMG_NAME}" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait

# Staple
echo ">>> Stapling notarization ticket..."
xcrun stapler staple "$BUILD_DIR/${DMG_NAME}"

# Verify staple
echo ">>> Verifying staple..."
xcrun stapler validate "$BUILD_DIR/${DMG_NAME}"

# Move to releases
mv "$BUILD_DIR/${DMG_NAME}" "$OUTPUT_DIR/"

# Generate checksums
echo ">>> Generating checksums..."
cd "$OUTPUT_DIR"
shasum -a 256 "$DMG_NAME" > "${DMG_NAME}.sha256"
SHA256=$(cat "${DMG_NAME}.sha256" | awk '{print $1}')

echo ""
echo "=============================================="
echo "BUILD COMPLETE!"
echo "=============================================="
echo ""
echo "DMG: $OUTPUT_DIR/$DMG_NAME"
echo "SHA256: $SHA256"
echo ""
echo "Next steps:"
echo "1. Generate appcast: ./scripts/generate_appcast.sh"
echo "2. Upload DMG to GitHub release"
echo "3. Deploy appcast.xml to sanehosts.com"
echo ""
