#!/usr/bin/env bash

# Sourced by both app-bundle builders after ROOT_DIR is set. These values are
# written into Info.plist so an installed binary identifies its exact source
# line instead of presenting the shared upstream VERSION number alone.

GROKBUILD_SOURCE_REPOSITORY="${GROKBUILD_SOURCE_REPOSITORY:-https://github.com/schmitzjimmy1-star/grok-build-desktop}"
GROKBUILD_BUILD_CHANNEL="${GROKBUILD_BUILD_CHANNEL:-personal}"

if [ -z "${GROKBUILD_SOURCE_BRANCH:-}" ]; then
    GROKBUILD_SOURCE_BRANCH="$(git -C "$ROOT_DIR" branch --show-current 2>/dev/null || true)"
fi
GROKBUILD_SOURCE_BRANCH="${GROKBUILD_SOURCE_BRANCH:-source-archive}"

if [ -z "${GROKBUILD_SOURCE_COMMIT:-}" ]; then
    GROKBUILD_SOURCE_COMMIT="$(git -C "$ROOT_DIR" rev-parse --verify HEAD 2>/dev/null || true)"
fi
GROKBUILD_SOURCE_COMMIT="${GROKBUILD_SOURCE_COMMIT:-unknown}"

if [ -z "${GROKBUILD_SOURCE_DIRTY:-}" ]; then
    if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
        && git -C "$ROOT_DIR" diff --quiet \
        && git -C "$ROOT_DIR" diff --cached --quiet \
        && [ -z "$(git -C "$ROOT_DIR" ls-files --others --exclude-standard)" ]; then
        GROKBUILD_SOURCE_DIRTY="false"
    else
        GROKBUILD_SOURCE_DIRTY="true"
    fi
fi

case "$GROKBUILD_SOURCE_DIRTY" in
    true|false) ;;
    *)
        echo "ERROR: GROKBUILD_SOURCE_DIRTY must be true or false." >&2
        return 1 2>/dev/null || exit 1
        ;;
esac

grokbuild_plist_escape() {
    local value="$1"
    value="${value//&/&amp;}"
    value="${value//</&lt;}"
    value="${value//>/&gt;}"
    printf '%s' "$value"
}

GROKBUILD_SOURCE_REPOSITORY_XML="$(grokbuild_plist_escape "$GROKBUILD_SOURCE_REPOSITORY")"
GROKBUILD_BUILD_CHANNEL_XML="$(grokbuild_plist_escape "$GROKBUILD_BUILD_CHANNEL")"
GROKBUILD_SOURCE_BRANCH_XML="$(grokbuild_plist_escape "$GROKBUILD_SOURCE_BRANCH")"
GROKBUILD_SOURCE_COMMIT_XML="$(grokbuild_plist_escape "$GROKBUILD_SOURCE_COMMIT")"
