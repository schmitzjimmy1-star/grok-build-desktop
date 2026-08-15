#!/usr/bin/env bash
set -euo pipefail

# Build a lightweight GrokBuild.app bundle for local development.
# Uses the same bundle identifier as the packaged app so Accessibility
# entries from System Settings apply to `make run` launches.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-identity.sh"
APP_NAME="GrokBuild"
EXECUTABLE_NAME="GrokBuild"
APP_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
BUILD_DIR="$ROOT_DIR/.build"
BUILD_CONFIG="${BUILD_CONFIG:-release}"
BINARY_DIR="$BUILD_DIR/$BUILD_CONFIG"
APP_BUNDLE="$BUILD_DIR/${APP_NAME}.app"

if [ ! -x "$BINARY_DIR/$EXECUTABLE_NAME" ]; then
    echo "Missing $BUILD_CONFIG binary at $BINARY_DIR/$EXECUTABLE_NAME. Run 'make build' or 'make build-debug' first." >&2
    exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY_DIR/$EXECUTABLE_NAME" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

if [ -f "$BINARY_DIR/GrokBuildComputerUseMCP" ]; then
    cp "$BINARY_DIR/GrokBuildComputerUseMCP" "$APP_BUNDLE/Contents/MacOS/GrokBuildComputerUseMCP"
    chmod +x "$APP_BUNDLE/Contents/MacOS/GrokBuildComputerUseMCP"
fi

if [ -f "$ROOT_DIR/scripts/grokbuild-browser-mcp" ]; then
    cp "$ROOT_DIR/scripts/grokbuild-browser-mcp" "$APP_BUNDLE/Contents/Resources/grokbuild-browser-mcp"
    chmod +x "$APP_BUNDLE/Contents/Resources/grokbuild-browser-mcp"
fi

if [ -f "$ROOT_DIR/scripts/grokbuild-install-update.sh" ]; then
    cp "$ROOT_DIR/scripts/grokbuild-install-update.sh" "$APP_BUNDLE/Contents/Resources/grokbuild-install-update"
    chmod +x "$APP_BUNDLE/Contents/Resources/grokbuild-install-update"
fi

if [ -d "$ROOT_DIR/GrokBuild/Resources/Skills" ]; then
    mkdir -p "$APP_BUNDLE/Contents/Resources/Skills"
    cp -R "$ROOT_DIR/GrokBuild/Resources/Skills/." "$APP_BUNDLE/Contents/Resources/Skills/"
fi

# Copy the Grok brand mark so GrokBrandIcon.mark() resolves it in the dev bundle
# (brand mark + welcome state). Without this the app falls back to an SF Symbol.
ICONSET_DIR="$ROOT_DIR/GrokBuild/Resources/Assets.xcassets/MenuBarIcon.imageset"
for icon in MenuBarIcon.png MenuBarIcon@2x.png MenuBarIcon@3x.png; do
    if [ -f "$ICONSET_DIR/$icon" ]; then
        cp "$ICONSET_DIR/$icon" "$APP_BUNDLE/Contents/Resources/$icon"
    fi
done

# Keep `make run` on the same vector-to-ICNS contract as `make ship`.
"$SCRIPT_DIR/package-app-icon.sh" "$ROOT_DIR" "$BUILD_DIR" "$APP_BUNDLE"

chmod +x "$SCRIPT_DIR/bundle-agent-desktop.sh" "$SCRIPT_DIR/codesign-app-bundle.sh"
# Computer Use is a first-class feature: a build without agent-desktop is
# broken, so bundling failures fail the build unless explicitly waived.
if [ "${GROKBUILD_ALLOW_MISSING_AGENT_DESKTOP:-0}" = "1" ]; then
    "$SCRIPT_DIR/bundle-agent-desktop.sh" "$APP_BUNDLE/Contents/MacOS" \
        || echo "WARNING: continuing WITHOUT agent-desktop — Computer Use will not work in this build."
else
    "$SCRIPT_DIR/bundle-agent-desktop.sh" "$APP_BUNDLE/Contents/MacOS"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.grokbuild.app</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_VERSION</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>GrokBuildBuildChannel</key>
    <string>$GROKBUILD_BUILD_CHANNEL_XML</string>
    <key>GrokBuildSourceRepository</key>
    <string>$GROKBUILD_SOURCE_REPOSITORY_XML</string>
    <key>GrokBuildSourceBranch</key>
    <string>$GROKBUILD_SOURCE_BRANCH_XML</string>
    <key>GrokBuildSourceCommit</key>
    <string>$GROKBUILD_SOURCE_COMMIT_XML</string>
    <key>GrokBuildSourceDirty</key>
    <$GROKBUILD_SOURCE_DIRTY/>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>GrokBuild uses the microphone for voice control in the chat composer.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>GrokBuild transcribes your speech to text for chat messages using voice control.</string>
</dict>
</plist>
EOF

# Sign with SIGN_IDENTITY from .env when present. Ad-hoc signatures get a new
# CDHash on every build, so macOS drops Accessibility/Screen Recording grants
# after each `make run`; a stable identity makes those grants persist.
"$SCRIPT_DIR/codesign-app-bundle.sh" "$APP_BUNDLE" "${SIGN_IDENTITY:--}"
echo "Dev app ready: $APP_BUNDLE"
