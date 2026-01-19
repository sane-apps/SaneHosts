#!/bin/bash
# SaneHosts clean build and launch script
# Kills all running instances and stale builds before launching

set -e

PROJECT_DIR="/Users/sj/SaneApps/apps/SaneHosts"
DERIVED_DATA_BASE="$HOME/Library/Developer/Xcode/DerivedData"

echo "=== SaneHosts Clean Launch ==="

# 1. Kill all running SaneHosts instances
echo "Killing any running SaneHosts..."
killall SaneHosts 2>/dev/null || true
sleep 1

# Double-check nothing is running
if pgrep -x SaneHosts > /dev/null; then
    echo "Force killing remaining processes..."
    pkill -9 -x SaneHosts 2>/dev/null || true
    sleep 1
fi

# 2. Clean up stale DerivedData directories (keep only newest)
echo "Cleaning stale DerivedData..."
SANE_DIRS=$(ls -dt "$DERIVED_DATA_BASE"/SaneHosts-* 2>/dev/null | tail -n +2)
if [ -n "$SANE_DIRS" ]; then
    echo "$SANE_DIRS" | while read dir; do
        echo "  Removing: $(basename "$dir")"
        rm -rf "$dir"
    done
fi

# 3. Build
echo "Building..."
cd "$PROJECT_DIR"
xcodebuild -workspace SaneHosts.xcworkspace \
    -scheme SaneHosts \
    -configuration Debug \
    -arch arm64 \
    build 2>&1 | grep -E "BUILD|error:" || true

# 4. Find and launch the app
APP_PATH=$(ls -dt "$DERIVED_DATA_BASE"/SaneHosts-*/Build/Products/Debug/SaneHosts.app 2>/dev/null | head -1)
if [ -z "$APP_PATH" ]; then
    echo "ERROR: App not found after build"
    exit 1
fi

echo "Launching: $APP_PATH"
open "$APP_PATH"

# 5. Verify single instance
sleep 2
PIDS=$(pgrep -x SaneHosts)
PID_COUNT=$(echo "$PIDS" | wc -l | tr -d ' ')
echo "Running instances: $PID_COUNT (PID: $PIDS)"

if [ "$PID_COUNT" -gt 1 ]; then
    echo "WARNING: Multiple instances detected!"
fi

echo "=== Done ==="
