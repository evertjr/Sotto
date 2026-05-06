#!/usr/bin/env bash
# release.sh — Build, sign, and publish a Sotto release.
#
# Prerequisites (do these first, in this order):
#   1. Bump MARKETING_VERSION and CURRENT_PROJECT_VERSION in Sotto.xcodeproj/project.pbxproj
#   2. Commit the bump on main
#   3. In Xcode: Product → Archive → Distribute → Developer ID (notarizes automatically)
#   4. Export the .app from Organizer to ~/Downloads/Sotto.app
#   5. Write release notes (Markdown) to a file, e.g. /tmp/release-notes.md
#
# Then run:
#   scripts/release.sh --notes /tmp/release-notes.md
#
# What this script does (and what it asks before doing):
#   - Builds a DMG with the standard drag-to-install layout
#   - Signs the DMG with the Sparkle key (account: sotto)
#   - Updates appcast.xml with a new <item> for this version
#   - PROMPTS before any push/tag/release action
#   - Pushes pending commits, tags v$VERSION, runs `gh release create` with the DMG
#   - Commits and pushes the updated appcast.xml
#
# Options:
#   --notes FILE     Markdown release notes (REQUIRED)
#   --version X.Y.Z  Override version detection from pbxproj
#   --dry-run        Build DMG and update appcast.xml locally; skip all push/tag/release
#   -h, --help       Show this help

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

NOTES_FILE=""
VERSION_OVERRIDE=""
DRY_RUN=false

usage() {
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --notes) NOTES_FILE="$2"; shift 2 ;;
    --version) VERSION_OVERRIDE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# ---- Validation -------------------------------------------------------------

[[ -n "$NOTES_FILE" ]] || { echo "ERROR: --notes FILE is required" >&2; exit 1; }
[[ -f "$NOTES_FILE" ]] || { echo "ERROR: notes file not found: $NOTES_FILE" >&2; exit 1; }
[[ -d "$HOME/Downloads/Sotto.app" ]] || {
  echo "ERROR: ~/Downloads/Sotto.app not found." >&2
  echo "       Archive in Xcode → Distribute → Developer ID, then export to ~/Downloads." >&2
  exit 1
}

PBXPROJ="Sotto.xcodeproj/project.pbxproj"
[[ -f "$PBXPROJ" ]] || { echo "ERROR: $PBXPROJ not found — run from repo root" >&2; exit 1; }

if [[ -n "$VERSION_OVERRIDE" ]]; then
  VERSION="$VERSION_OVERRIDE"
else
  VERSION=$(grep -E "MARKETING_VERSION = " "$PBXPROJ" | head -1 | sed -E 's/.*= ([^;]+);.*/\1/')
fi
BUILD=$(grep -E "CURRENT_PROJECT_VERSION = " "$PBXPROJ" | head -1 | sed -E 's/.*= ([^;]+);.*/\1/')

[[ -n "$VERSION" && -n "$BUILD" ]] || { echo "ERROR: could not parse version/build from pbxproj" >&2; exit 1; }

APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$HOME/Downloads/Sotto.app/Contents/Info.plist")
APP_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$HOME/Downloads/Sotto.app/Contents/Info.plist")

if [[ "$APP_VERSION" != "$VERSION" || "$APP_BUILD" != "$BUILD" ]]; then
  echo "ERROR: version mismatch between pbxproj and the exported .app." >&2
  echo "       pbxproj: $VERSION (build $BUILD)" >&2
  echo "       app:     $APP_VERSION (build $APP_BUILD)" >&2
  echo "       Re-archive after bumping the version, or use --version to override." >&2
  exit 1
fi

# Working tree must be clean (we'll be committing appcast.xml ourselves)
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "ERROR: working tree has uncommitted changes. Commit or stash first." >&2
  git status --short
  exit 1
fi

BRANCH=$(git symbolic-ref --short HEAD)
[[ "$BRANCH" == "main" ]] || { echo "ERROR: not on main (on $BRANCH)" >&2; exit 1; }

# Find sign_update inside DerivedData (Sparkle ships it as a build artifact)
SIGN_UPDATE=$(find "$HOME/Library/Developer/Xcode/DerivedData" \
  -path "*/sparkle/Sparkle/bin/sign_update" -type f 2>/dev/null \
  | grep -v old_dsa_scripts \
  | head -1)
[[ -x "$SIGN_UPDATE" ]] || {
  echo "ERROR: sign_update not found in DerivedData." >&2
  echo "       Build a project that depends on Sparkle once so Xcode fetches it." >&2
  exit 1
}

command -v create-dmg >/dev/null || { echo "ERROR: create-dmg not installed (brew install create-dmg)" >&2; exit 1; }
command -v gh >/dev/null || { echo "ERROR: gh not installed" >&2; exit 1; }

# Tag must not already exist
if git rev-parse "v$VERSION" >/dev/null 2>&1; then
  echo "ERROR: tag v$VERSION already exists locally" >&2
  exit 1
fi
if git ls-remote --tags origin "v$VERSION" | grep -q "v$VERSION"; then
  echo "ERROR: tag v$VERSION already exists on origin" >&2
  exit 1
fi

echo "==> Releasing Sotto $VERSION (build $BUILD)"
echo "    Notes:  $NOTES_FILE"
echo "    App:    ~/Downloads/Sotto.app"

# ---- Build DMG --------------------------------------------------------------

DMG_PATH="$HOME/Downloads/Sotto-$VERSION.dmg"
echo "==> Building DMG: $DMG_PATH"
rm -f "$DMG_PATH"
create-dmg \
  --volname "Sotto" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 128 \
  --icon "Sotto.app" 175 190 \
  --hide-extension "Sotto.app" \
  --app-drop-link 425 190 \
  "$DMG_PATH" \
  "$HOME/Downloads/Sotto.app" >/dev/null

# ---- Sign DMG ---------------------------------------------------------------

echo "==> Signing DMG"
SIGN_OUTPUT=$("$SIGN_UPDATE" --account sotto "$DMG_PATH")
ED_SIG=$(echo "$SIGN_OUTPUT" | sed -E 's/.*sparkle:edSignature="([^"]+)".*/\1/')
DMG_SIZE=$(stat -f%z "$DMG_PATH")

[[ -n "$ED_SIG" && "$ED_SIG" != "$SIGN_OUTPUT" ]] || {
  echo "ERROR: failed to parse edSignature from sign_update output: $SIGN_OUTPUT" >&2
  exit 1
}

echo "    edSignature: $ED_SIG"
echo "    length:      $DMG_SIZE"

# ---- Update appcast.xml -----------------------------------------------------

echo "==> Updating appcast.xml"
PUB_DATE=$(LC_ALL=C date -u +"%a, %d %b %Y %H:%M:%S +0000")

# Convert markdown notes to basic HTML for the appcast description
HTML_NOTES=$(python3 - "$NOTES_FILE" <<'PY'
import re, sys

def inline(s):
    s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
    s = re.sub(r"\*([^*]+)\*", r"<em>\1</em>", s)
    s = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', s)
    return s

with open(sys.argv[1]) as f:
    text = f.read()

out, in_ul = [], False
for raw in text.splitlines():
    line = raw.rstrip()
    if not line:
        if in_ul:
            out.append("</ul>"); in_ul = False
        continue
    m = re.match(r"^(#{1,6})\s+(.+)$", line)
    if m:
        if in_ul:
            out.append("</ul>"); in_ul = False
        n = len(m.group(1))
        out.append(f"<h{n}>{inline(m.group(2))}</h{n}>")
        continue
    m = re.match(r"^[-*]\s+(.+)$", line)
    if m:
        if not in_ul:
            out.append("<ul>"); in_ul = True
        out.append(f"<li>{inline(m.group(1))}</li>")
        continue
    if in_ul:
        out.append("</ul>"); in_ul = False
    out.append(f"<p>{inline(line)}</p>")
if in_ul:
    out.append("</ul>")
print("\n        ".join(out))
PY
)

# Build the new <item>. Indented to match the existing 4-space indent inside <channel>.
NEW_ITEM=$(cat <<EOF
    <item>
      <title>Version $VERSION</title>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <description><![CDATA[
        $HTML_NOTES
      ]]></description>
      <pubDate>$PUB_DATE</pubDate>
      <enclosure
        url="https://github.com/evertjr/Sotto/releases/download/v$VERSION/Sotto-$VERSION.dmg"
        sparkle:edSignature="$ED_SIG"
        length="$DMG_SIZE"
        type="application/octet-stream" />
    </item>
EOF
)

# Insert the new item before the first existing <item>
python3 - "$NEW_ITEM" <<'PY'
import sys
new_item = sys.argv[1]
path = "appcast.xml"
with open(path) as f:
    content = f.read()
marker = "    <item>"
idx = content.find(marker)
if idx == -1:
    sys.exit("ERROR: could not find <item> marker in appcast.xml")
content = content[:idx] + new_item + "\n" + content[idx:]
with open(path, "w") as f:
    f.write(content)
PY

echo "    appcast.xml updated"

# ---- Confirm ----------------------------------------------------------------

if $DRY_RUN; then
  echo ""
  echo "==> Dry run complete. DMG and appcast.xml are ready locally; nothing pushed."
  echo "    DMG:     $DMG_PATH"
  echo "    Appcast: $REPO_ROOT/appcast.xml (uncommitted)"
  exit 0
fi

echo ""
echo "About to:"
echo "  1. git push origin main         (any pending source commits, e.g. the version bump)"
echo "  2. git tag v$VERSION && git push origin v$VERSION"
echo "  3. gh release create v$VERSION $DMG_PATH --notes-file $NOTES_FILE"
echo "  4. git commit appcast.xml + git push origin main"
echo ""
read -r -p "Proceed? [y/N] " REPLY
[[ "$REPLY" =~ ^[Yy]$ ]] || { echo "Aborted. appcast.xml has been edited but not committed."; exit 1; }

# ---- Publish ----------------------------------------------------------------

echo "==> Pushing main"
git push origin main

echo "==> Tagging v$VERSION"
git tag "v$VERSION"
git push origin "v$VERSION"

echo "==> Creating GitHub release"
gh release create "v$VERSION" "$DMG_PATH" \
  --title "Sotto $VERSION" \
  --notes-file "$NOTES_FILE"

echo "==> Committing appcast.xml"
git add appcast.xml
git commit -m "Update appcast for v$VERSION"
git push origin main

echo ""
echo "Released! https://github.com/evertjr/Sotto/releases/tag/v$VERSION"
