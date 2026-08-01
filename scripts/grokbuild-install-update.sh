#!/usr/bin/env bash
set -euo pipefail

TARGET=""
NEW_APP=""
PID=""
RELAUNCH=1
RELAUNCH_ONLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)
            TARGET="$2"
            shift 2
            ;;
        --new-app)
            NEW_APP="$2"
            shift 2
            ;;
        --pid)
            PID="$2"
            shift 2
            ;;
        --relaunch-only)
            RELAUNCH_ONLY=1
            shift
            ;;
        --no-relaunch)
            RELAUNCH=0
            shift
            ;;
        -h|--help)
            echo "Usage: $0 --target PATH (--new-app PATH | --relaunch-only) --pid PID [--no-relaunch]"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

if [[ -z "$TARGET" || -z "$PID" ]]; then
    echo "Missing required arguments." >&2
    echo "Usage: $0 --target PATH (--new-app PATH | --relaunch-only) --pid PID [--no-relaunch]" >&2
    exit 2
fi

if [[ "$RELAUNCH_ONLY" -eq 0 ]]; then
    if [[ -z "$NEW_APP" ]]; then
        echo "Missing --new-app (or pass --relaunch-only)." >&2
        exit 2
    fi
    if [[ ! -d "$NEW_APP" ]]; then
        echo "New app bundle not found: $NEW_APP" >&2
        exit 1
    fi
fi

if [[ ! -d "$TARGET" ]]; then
    echo "Target app bundle not found: $TARGET" >&2
    exit 1
fi

for _ in $(seq 1 120); do
    if ! kill -0 "$PID" 2>/dev/null; then
        break
    fi
    sleep 0.5
done

if kill -0 "$PID" 2>/dev/null; then
    echo "Timed out waiting for process $PID to exit." >&2
    exit 1
fi

if [[ "$RELAUNCH_ONLY" -eq 0 ]]; then
    # Stage-then-swap instead of ditto-merging into the live bundle: a merge kept
    # files deleted upstream (slowly breaking the signature seal) and a mid-copy
    # failure could leave a hybrid install. Staging beside the target keeps both
    # renames on one volume, so the swap window is two atomic mv calls with a
    # rollback path.
    PARENT="$(dirname "$TARGET")"
    BASE="$(basename "$TARGET" .app)"
    STAGED="$PARENT/.$BASE.update-$$.app"
    PREVIOUS="$PARENT/.$BASE.previous-$$.app"
    rm -rf "$STAGED" "$PREVIOUS"
    cleanup_staging() { rm -rf "$STAGED" "$PREVIOUS"; }
    trap cleanup_staging EXIT

    ditto "$NEW_APP" "$STAGED"

    # Verify the exact bytes that will become the installed app, and only then
    # clear quarantine — on that verified content, never on unchecked files.
    if ! codesign --verify --deep --strict "$STAGED" >/dev/null 2>&1; then
        echo "Staged update failed code signature verification; leaving the installed app untouched." >&2
        exit 1
    fi
    xattr -cr "$STAGED" 2>/dev/null || true

    mv "$TARGET" "$PREVIOUS"
    if ! mv "$STAGED" "$TARGET"; then
        mv "$PREVIOUS" "$TARGET"
        echo "Could not move the staged update into place; previous app restored." >&2
        exit 1
    fi
fi

if [[ "$RELAUNCH_ONLY" -eq 1 || "$RELAUNCH" -eq 1 ]]; then
    open "$TARGET"
fi
