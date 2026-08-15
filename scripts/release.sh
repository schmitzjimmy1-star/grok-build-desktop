#!/usr/bin/env bash
set -euo pipefail

# Build and publish a GitHub release (mirrors .github/workflows/release.yml).
#
# This personal line installs with `make ship` under Apple Development
# (Team DD2GCQJVB4). It does not publish notarized GitHub releases.
# `RELEASE_TYPE=notarized` is refused.
#
# Publication target is the personal remote only:
#   personal → schmitzjimmy1-star/grok-build-desktop
# `origin` (rimusz/grok-build-desktop) is read-only upstream. This script
# never pushes tags to origin and never force-updates a release tag.
#
# Usage:
#   make ship
#   make release                 # unsigned personal GitHub release only, if explicitly asked
#   make release RELEASE_VERSION=v0.1.4   # must match VERSION file

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

# shellcheck source=load-dotenv.sh
source "$SCRIPT_DIR/load-dotenv.sh"
load_dotenv "$ROOT_DIR/.env"

APP_NAME="${APP_NAME:-GrokBuild}"
RELEASE_TYPE="${RELEASE_TYPE:-unsigned}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_PASSWORD}"

app_version="$(tr -d '[:space:]' < VERSION)"
default_tag="v${app_version}"
input_version="${RELEASE_VERSION:-}"

if [ -n "$input_version" ]; then
  case "$input_version" in
    v*) tag_name="$input_version" ;;
    *) tag_name="v${input_version}" ;;
  esac
else
  tag_name="$default_tag"
fi

if [ "$tag_name" != "$default_tag" ]; then
  echo "ERROR: Release tag '$tag_name' does not match VERSION '$default_tag'. Update VERSION or set RELEASE_VERSION."
  exit 1
fi

if [ "$RELEASE_TYPE" = "notarized" ]; then
  echo "ERROR: This personal line does not publish notarized GitHub releases."
  echo "Install with: make ship"
  echo "Signing identity is Apple Development on this Mac (Team DD2GCQJVB4)."
  echo "Do not chase Developer ID or notary profiles."
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: gh CLI is required. Install with: brew install gh && gh auth login"
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "ERROR: gh is not authenticated. Run: gh auth login"
  exit 1
fi

PERSONAL_OWNER="schmitzjimmy1-star"
PERSONAL_REPO="grok-build-desktop"
PERSONAL_SLUG="${PERSONAL_OWNER}/${PERSONAL_REPO}"

create_dmg() {
  make dmg-package
}

write_release_notes() {
  local output_file="$1"
  local zip_name="${APP_NAME}-${tag_name}.app.zip"
  local dmg_name="${APP_NAME}-${tag_name}-macOS.dmg"

  if [ "$RELEASE_TYPE" = "notarized" ]; then
    cat > "$output_file" <<EOF
## Downloads

- \`${zip_name}\` — Signed + notarized build (recommended)
- \`${dmg_name}\` — Signed + notarized DMG

This version is properly code-signed and notarized. No Gatekeeper warnings.
EOF
  else
    cat > "$output_file" <<EOF
## Downloads

- \`${zip_name}\` — Unsigned build
- \`${dmg_name}\` — Unsigned DMG

## How to bypass Gatekeeper protection (unsigned builds)

macOS may block unsigned apps.

**Quick ways to open:**

1. Right-click \`GrokBuild.app\` (or the DMG) → **Open**
2. Terminal: \`xattr -cr ~/Applications/GrokBuild.app\`
3. System Settings → Privacy & Security → "Open Anyway"

---

For a signed + notarized version with no warnings, set in \`.env\`:

    RELEASE_TYPE=notarized
    SIGN_IDENTITY=Developer ID Application: ...
    NOTARY_PROFILE=AC_PASSWORD

Then run \`make release\`.
EOF
  fi
}

publication_remote() {
  if ! git remote get-url personal >/dev/null 2>&1; then
    echo "ERROR: remote 'personal' is required and must point at ${PERSONAL_SLUG}."
    exit 1
  fi
  local url
  url="$(git remote get-url personal)"
  case "$url" in
    *"${PERSONAL_SLUG}"*) ;;
    *)
      echo "ERROR: remote 'personal' is '${url}'; expected ${PERSONAL_SLUG}."
      exit 1
      ;;
  esac
  echo "personal"
}

commit_for_tag() {
  git rev-parse "${1}^{}"
}

ensure_release_tag() {
  local tag="$1"
  local remote
  remote="$(publication_remote)"
  local head_sha
  head_sha="$(git rev-parse HEAD)"

  if git rev-parse "$tag" >/dev/null 2>&1; then
    local tag_sha
    tag_sha="$(commit_for_tag "$tag")"
    if [ "$tag_sha" != "$head_sha" ]; then
      echo "ERROR: local tag ${tag} is at ${tag_sha:0:7}, HEAD is ${head_sha:0:7}."
      echo "Refusing to move an existing tag."
      echo "If this tag was fetched from origin (rimusz/grok-build-desktop), delete it locally only:"
      echo "  git tag -d ${tag}"
      echo "Never run: git push --delete origin ${tag}"
      echo "Then re-run so ${tag} is created at this HEAD and pushed to personal only."
      exit 1
    fi
  else
    echo "==> Creating tag ${tag} at HEAD..."
    git tag "$tag"
  fi

  local remote_sha=""
  remote_sha="$(git ls-remote --tags "$remote" "refs/tags/${tag}^{}" 2>/dev/null | awk '{print $1}' | head -1)"
  if [ -z "$remote_sha" ]; then
    remote_sha="$(git ls-remote --tags "$remote" "refs/tags/${tag}" 2>/dev/null | awk '{print $1}' | head -1)"
  fi
  local tag_sha
  tag_sha="$(commit_for_tag "$tag")"

  if [ -z "$remote_sha" ]; then
    echo "==> Pushing ${tag} to ${remote} (${PERSONAL_SLUG})..."
    git push "$remote" "$tag"
  elif [ "$remote_sha" != "$tag_sha" ]; then
    echo "ERROR: ${remote} already has ${tag} at ${remote_sha:0:7}; local is ${tag_sha:0:7}."
    echo "Refusing to force-update a release tag on ${PERSONAL_SLUG}."
    exit 1
  else
    echo "==> ${remote} already has ${tag} at HEAD."
  fi
}

publication_remote >/dev/null

origin_tag_sha="$(git ls-remote --tags origin "refs/tags/${tag_name}^{}" 2>/dev/null | awk '{print $1}' | head -1)"
if [ -z "$origin_tag_sha" ]; then
  origin_tag_sha="$(git ls-remote --tags origin "refs/tags/${tag_name}" 2>/dev/null | awk '{print $1}' | head -1)"
fi
if [ -n "$origin_tag_sha" ]; then
  echo "WARN: origin (rimusz/grok-build-desktop) already has ${tag_name} at ${origin_tag_sha:0:7}."
  echo "That tag is upstream's, not ours. This release still publishes to personal only."
  echo "Do not delete or move the origin tag."
fi

if [ "$RELEASE_TYPE" = "notarized" ]; then
  if [ -z "$SIGN_IDENTITY" ]; then
    echo "ERROR: SIGN_IDENTITY is required for notarized releases (set in .env or environment)."
    exit 1
  fi
  case "$SIGN_IDENTITY" in
    "Developer ID Application"*) ;;
    *)
      echo "ERROR: notarized releases require SIGN_IDENTITY to start with 'Developer ID Application'."
      echo "Apple Development identities cannot be notarized. Do not title an unsigned or development-signed build (Notarized)."
      exit 1
      ;;
  esac
fi

zip_path="dist/${APP_NAME}-${tag_name}.app.zip"
dmg_path="dist/${APP_NAME}-${tag_name}-macOS.dmg"
dmg_staging="dist/${APP_NAME}-macOS.dmg"
release_body_file="$(mktemp)"
trap 'rm -f "$release_body_file"' EXIT

echo "==> Building ${RELEASE_TYPE} release for ${tag_name}..."
if [ "$RELEASE_TYPE" = "notarized" ]; then
  echo "==> Signing with: ${SIGN_IDENTITY}"
fi

if [ "$RELEASE_TYPE" = "notarized" ]; then
  make signed SIGN_IDENTITY="$SIGN_IDENTITY"
  NOTARY_PROFILE="$NOTARY_PROFILE" ./scripts/notarize.sh "dist/${APP_NAME}.app"
  echo "==> Creating DMG from notarized app..."
  create_dmg
else
  make app
  echo "==> Creating DMG..."
  create_dmg
fi

if [ "$RELEASE_TYPE" = "notarized" ]; then
  release_name="${tag_name} (Notarized)"
else
  release_name="${tag_name} (Unsigned)"
fi

echo "==> Zipping app..."
ditto -c -k --keepParent "dist/${APP_NAME}.app" "$zip_path"
cp "$dmg_staging" "$dmg_path"
echo "==> Release assets: $(basename "$zip_path"), $(basename "$dmg_path")"

write_release_notes "$release_body_file"

ensure_release_tag "$tag_name"

echo "==> Publishing GitHub release ${tag_name}..."

if gh release view "$tag_name" --repo "$PERSONAL_SLUG" >/dev/null 2>&1; then
  echo "==> Release ${tag_name} already exists on ${PERSONAL_SLUG}; updating title, notes, and assets..."
  gh release edit "$tag_name" --repo "$PERSONAL_SLUG" --title "$release_name" --notes-file "$release_body_file"
  gh release upload "$tag_name" --repo "$PERSONAL_SLUG" "$zip_path" "$dmg_path" --clobber
else
  gh release create "$tag_name" \
    --repo "$PERSONAL_SLUG" \
    --title "$release_name" \
    --draft \
    --generate-notes \
    "$zip_path" \
    "$dmg_path"

  generated_notes="$(gh release view "$tag_name" --repo "$PERSONAL_SLUG" --json body -q .body)"
  {
    cat "$release_body_file"
    echo ""
    echo "---"
    echo ""
    printf '%s\n' "$generated_notes"
  } > "${release_body_file}.combined"
  mv "${release_body_file}.combined" "$release_body_file"

  gh release edit "$tag_name" --repo "$PERSONAL_SLUG" --notes-file "$release_body_file" --draft=false
fi

release_url="$(gh release view "$tag_name" --repo "$PERSONAL_SLUG" --json url -q .url)"
echo "==> Published: ${release_url}"
if [[ "$release_url" != *"${PERSONAL_SLUG}"* ]]; then
  echo "ERROR: release URL is not on ${PERSONAL_SLUG}: ${release_url}"
  exit 1
fi
