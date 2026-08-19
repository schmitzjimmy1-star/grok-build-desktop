#!/usr/bin/env bash
# Copy agent-desktop into an app bundle's Contents/MacOS directory.
# Usage: bundle-agent-desktop.sh /path/to/GrokBuild.app/Contents/MacOS

set -euo pipefail

DEST_DIR="${1:?destination MacOS directory required}"
SRC=""

if [ -n "${AGENT_DESKTOP_PATH:-}" ] && [ -x "${AGENT_DESKTOP_PATH}" ]; then
    SRC="${AGENT_DESKTOP_PATH}"
else
    for candidate in \
        "${HOME}/.grokbuild/computer-use/agent-desktop" \
        /opt/homebrew/bin/agent-desktop \
        /usr/local/bin/agent-desktop \
        "${HOME}/.local/bin/agent-desktop" \
        "${HOME}/bin/agent-desktop"; do
        if [ -x "$candidate" ]; then
            SRC="$candidate"
            break
        fi
    done
fi

if [ -z "$SRC" ] && [ -n "${PATH:-}" ]; then
    IFS=':' read -ra path_dirs <<< "$PATH"
    for dir in "${path_dirs[@]}"; do
        if [ -x "$dir/agent-desktop" ]; then
            SRC="$dir/agent-desktop"
            break
        fi
    done
fi

if [ -z "$SRC" ]; then
    echo "ERROR: agent-desktop not found on this machine — Computer Use cannot work without it." >&2
    echo "       Install it with: npm install -g agent-desktop" >&2
    echo "       (or set AGENT_DESKTOP_PATH, or build with GROKBUILD_ALLOW_MISSING_AGENT_DESKTOP=1" >&2
    echo "        to knowingly package an app whose Computer Use is non-functional)." >&2
    return 1 2>/dev/null || exit 1
fi

cp "$SRC" "$DEST_DIR/agent-desktop"
chmod +x "$DEST_DIR/agent-desktop"

# A copied npm shim that require()s sibling files would pass `test -x` and
# still be broken — prove the bundled copy actually runs.
if ! "$DEST_DIR/agent-desktop" version >/dev/null 2>&1; then
    echo "ERROR: bundled agent-desktop (copied from $SRC) failed to run 'version'." >&2
    echo "       The source may be a launcher shim rather than a standalone binary." >&2
    exit 1
fi

echo "==> Bundled agent-desktop from $SRC"
