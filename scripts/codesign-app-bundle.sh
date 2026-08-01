#!/usr/bin/env bash
# Sign GrokBuild.app so nested tools share com.grokbuild.app for Accessibility.
# Usage: codesign-app-bundle.sh /path/to/GrokBuild.app [signing_identity]

set -euo pipefail

APP_BUNDLE="${1:?app bundle path required}"
IDENTITY="${2:--}"
BUNDLE_ID="com.grokbuild.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"

xattr -cr "$APP_BUNDLE" 2>/dev/null || true

if [ "$IDENTITY" != "-" ]; then
    # Entitlements are prepared up front so nested helpers can be signed with
    # hardened runtime. The notary service requires hardened runtime + a secure
    # timestamp on every nested executable — helpers signed --timestamp=none
    # without runtime were a notarization-rejection risk.
    ENTITLEMENTS_PLIST="$(mktemp)"
    HELPER_JS_ENTITLEMENTS_PLIST="$(mktemp)"
    trap 'rm -f "$ENTITLEMENTS_PLIST" "$HELPER_JS_ENTITLEMENTS_PLIST"' EXIT
    cat > "$ENTITLEMENTS_PLIST" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
</dict>
</plist>
EOF
    # agent-desktop embeds a JavaScript runtime: under hardened runtime it needs
    # JIT + unsigned-executable-memory or it dies on launch.
    cat > "$HELPER_JS_ENTITLEMENTS_PLIST" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
</dict>
</plist>
EOF
fi

sign_nested() {
    local name="$1"
    shift
    local path="$MACOS_DIR/$name"
    [ -f "$path" ] || return 0
    echo "==> Signing $name as $BUNDLE_ID"
    if [ "$IDENTITY" = "-" ]; then
        # Ad-hoc signatures cannot carry secure timestamps.
        codesign --force --sign - --identifier "$BUNDLE_ID" --timestamp=none "$path"
    else
        codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" \
            --options runtime --timestamp "$@" "$path"
    fi
}

sign_nested "GrokBuild"
sign_nested "GrokBuildComputerUseMCP"
if [ "$IDENTITY" = "-" ]; then
    sign_nested "agent-desktop"
else
    sign_nested "agent-desktop" --entitlements "$HELPER_JS_ENTITLEMENTS_PLIST"
fi

if [ "$IDENTITY" = "-" ]; then
    echo "==> Ad-hoc signing app bundle (required for macOS Accessibility trust)"
    codesign --force --sign - --timestamp=none "$APP_BUNDLE"
else
    echo "==> Signing app bundle with identity: $IDENTITY"
    # No --deep: nested tools were just signed with --identifier
    # "$BUNDLE_ID" so one Accessibility grant covers all three, and --deep
    # would re-sign them with filename-derived identifiers and break that.
    codesign --force --sign "$IDENTITY" \
        --options runtime \
        --timestamp \
        --entitlements "$ENTITLEMENTS_PLIST" \
        "$APP_BUNDLE"
fi
