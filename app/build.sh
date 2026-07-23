#!/bin/bash

# Build script for ClaudeUsageBar

echo "Building ClaudeUsageBar..."

# Create fresh build directory (delete any stale build to avoid accumulated xattrs
# from prior signs, which can cause "resource fork / detritus" errors on codesign).
rm -rf build
mkdir -p build

# Create app bundle structure first
APP_NAME="ClaudeUsageBar.app"
APP_PATH="build/$APP_NAME"

mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

# Copy Info.plist
cp Info.plist "$APP_PATH/Contents/"

# Create icon if it doesn't exist
if [ ! -f "ClaudeUsageBar.icns" ]; then
    echo "Creating app icon..."
    ./make_app_icon.sh >/dev/null 2>&1
fi

# Copy icon to Resources
if [ -f "ClaudeUsageBar.icns" ]; then
    cp ClaudeUsageBar.icns "$APP_PATH/Contents/Resources/"
    # Update Info.plist to reference icon
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string ClaudeUsageBar" "$APP_PATH/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile ClaudeUsageBar" "$APP_PATH/Contents/Info.plist"
fi

# Compile the Swift app for arm64
swiftc -parse-as-library -o "$APP_PATH/Contents/MacOS/ClaudeUsageBar_arm64" \
    ClaudeUsageBar.swift \
    -framework SwiftUI \
    -framework AppKit \
    -framework WebKit \
    -target arm64-apple-macos12.0

# Compile for x86_64 (Intel)
swiftc -parse-as-library -o "$APP_PATH/Contents/MacOS/ClaudeUsageBar_x86_64" \
    ClaudeUsageBar.swift \
    -framework SwiftUI \
    -framework AppKit \
    -framework WebKit \
    -target x86_64-apple-macos12.0

# Create universal binary
lipo -create -output "$APP_PATH/Contents/MacOS/ClaudeUsageBar" \
    "$APP_PATH/Contents/MacOS/ClaudeUsageBar_arm64" \
    "$APP_PATH/Contents/MacOS/ClaudeUsageBar_x86_64"

# Clean up individual arch binaries
rm "$APP_PATH/Contents/MacOS/ClaudeUsageBar_arm64"
rm "$APP_PATH/Contents/MacOS/ClaudeUsageBar_x86_64"

# Create PkgInfo file
echo -n "APPL????" > "$APP_PATH/Contents/PkgInfo"

# Set proper permissions first
chmod 755 "$APP_PATH/Contents/MacOS/ClaudeUsageBar"

# Clean any "detritus" that codesign rejects: extended attributes, ._files, .DS_Store
xattr -cr "$APP_PATH"
find "$APP_PATH" -name '._*' -delete 2>/dev/null
find "$APP_PATH" -name '.DS_Store' -delete 2>/dev/null
dot_clean "$APP_PATH" 2>/dev/null

# Sign with a STABLE local identity so macOS keeps the app's designated
# requirement constant across rebuilds — that is what lets the Accessibility
# (global-shortcut) grant survive a rebuild instead of re-prompting every time.
#
# Default identity is the self-signed "ClaudeUsageBar Self-Signed" cert created
# in a dedicated keychain by setup_signing.sh (see repo notes). Override with
# SIGN_IDENTITY / SIGN_KEYCHAIN env vars, e.g. to use a real Developer ID.
SIGN_IDENTITY="${SIGN_IDENTITY:-ClaudeUsageBar Self-Signed}"
SIGN_KEYCHAIN="${SIGN_KEYCHAIN:-$HOME/Library/Keychains/claudeusagebar-signing.keychain-db}"

CODESIGN_ARGS=(--force --deep --sign "$SIGN_IDENTITY")
if [ -f "$SIGN_KEYCHAIN" ]; then
    security unlock-keychain -p "cub-local-signing" "$SIGN_KEYCHAIN" 2>/dev/null || true
    CODESIGN_ARGS+=(--keychain "$SIGN_KEYCHAIN")
fi

if codesign "${CODESIGN_ARGS[@]}" "$APP_PATH" 2>/dev/null; then
    echo "✅ App signed with identity: $SIGN_IDENTITY"
    if codesign --verify --verbose=2 "$APP_PATH" 2>&1 | grep -q "valid on disk"; then
        echo "✅ Signature verified (designated requirement is stable across rebuilds)"
    else
        echo "⚠️  Signature verification did not report 'valid on disk'." >&2
    fi
else
    echo "⚠️  Signing with '$SIGN_IDENTITY' failed — falling back to ad-hoc." >&2
    echo "   Note: ad-hoc changes the signature each build, so the Accessibility" >&2
    echo "   grant will need to be re-approved. Run setup_signing.sh to fix." >&2
    codesign --force --deep --sign - "$APP_PATH"
fi

echo "Build successful!"
echo "App bundle created at: $APP_PATH"
echo "Launching app..."
open "$APP_PATH"
