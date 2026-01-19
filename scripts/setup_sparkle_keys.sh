#!/bin/bash
set -e

# =============================================================================
# SaneHosts Sparkle Key Setup
# Generates EdDSA signing keys for secure Sparkle updates
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
KEYS_DIR="$PROJECT_DIR/keys"
XCCONFIG_FILE="$PROJECT_DIR/Config/Shared.xcconfig"

echo "=============================================="
echo "Sparkle EdDSA Key Setup"
echo "=============================================="

# Create keys directory
mkdir -p "$KEYS_DIR"

# Find Sparkle's generate_keys tool
SPARKLE_GENERATE=""

# Check common locations
LOCATIONS=(
    "/Users/sj/Library/Developer/Xcode/DerivedData/SaneHosts-*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys"
    "$HOME/Library/Developer/Xcode/DerivedData/*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys"
    "/Applications/Sparkle/bin/generate_keys"
)

for pattern in "${LOCATIONS[@]}"; do
    found=$(ls $pattern 2>/dev/null | head -1)
    if [ -n "$found" ] && [ -x "$found" ]; then
        SPARKLE_GENERATE="$found"
        break
    fi
done

if [ -z "$SPARKLE_GENERATE" ]; then
    echo ""
    echo "ERROR: Could not find Sparkle's generate_keys tool."
    echo ""
    echo "Options:"
    echo "1. Build the project first to download Sparkle package"
    echo "2. Download Sparkle manually from https://sparkle-project.org"
    echo "3. Run: xcodebuild -workspace SaneHosts.xcworkspace -scheme SaneHosts -resolvePackageDependencies"
    echo ""
    exit 1
fi

echo "Found Sparkle tools at: $(dirname "$SPARKLE_GENERATE")"

# Check if keys already exist
if [ -f "$KEYS_DIR/sparkle_private_key" ]; then
    echo ""
    echo "WARNING: Keys already exist at $KEYS_DIR/"
    echo "Delete them first if you want to regenerate."
    echo ""

    # Show existing public key
    if [ -f "$KEYS_DIR/sparkle_public_key" ]; then
        echo "Existing public key:"
        cat "$KEYS_DIR/sparkle_public_key"
    fi
    exit 0
fi

# Generate new keys
echo ""
echo ">>> Generating new EdDSA key pair..."
cd "$KEYS_DIR"

# Run generate_keys and capture output
OUTPUT=$("$SPARKLE_GENERATE" -p sparkle_private_key 2>&1)
echo "$OUTPUT"

# Extract public key from output
PUBLIC_KEY=$(echo "$OUTPUT" | grep -A1 "Public key" | tail -1 | tr -d ' ')

if [ -z "$PUBLIC_KEY" ]; then
    # Try alternative extraction
    PUBLIC_KEY=$(cat sparkle_public_key 2>/dev/null || echo "")
fi

if [ -z "$PUBLIC_KEY" ]; then
    echo ""
    echo "ERROR: Could not extract public key"
    echo "Check the output above and manually copy the public key"
    exit 1
fi

# Save public key
echo "$PUBLIC_KEY" > sparkle_public_key

echo ""
echo "=============================================="
echo "KEYS GENERATED!"
echo "=============================================="
echo ""
echo "Private key: $KEYS_DIR/sparkle_private_key"
echo "Public key:  $KEYS_DIR/sparkle_public_key"
echo ""
echo "Public key value:"
echo "$PUBLIC_KEY"
echo ""

# Update xcconfig
echo ">>> Updating Shared.xcconfig with public key..."

# Check if SUPublicEDKey already exists
if grep -q "INFOPLIST_KEY_SUPublicEDKey" "$XCCONFIG_FILE"; then
    # Update existing
    sed -i '' "s|INFOPLIST_KEY_SUPublicEDKey = .*|INFOPLIST_KEY_SUPublicEDKey = ${PUBLIC_KEY}|" "$XCCONFIG_FILE"
else
    # Add new line after the TODO comment
    sed -i '' "s|// TODO: Add SUPublicEDKey.*|INFOPLIST_KEY_SUPublicEDKey = ${PUBLIC_KEY}|" "$XCCONFIG_FILE"
fi

echo "Updated $XCCONFIG_FILE"
echo ""
echo "IMPORTANT:"
echo "1. KEEP sparkle_private_key SECRET - never commit to git!"
echo "2. Add 'keys/' to .gitignore"
echo "3. Back up the private key securely"
echo ""

# Add to gitignore if not present
if ! grep -q "^keys/" "$PROJECT_DIR/.gitignore" 2>/dev/null; then
    echo "" >> "$PROJECT_DIR/.gitignore"
    echo "# Sparkle signing keys (NEVER commit)" >> "$PROJECT_DIR/.gitignore"
    echo "keys/" >> "$PROJECT_DIR/.gitignore"
    echo "Added keys/ to .gitignore"
fi

echo "Done!"
