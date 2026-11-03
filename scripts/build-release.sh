#!/bin/bash
# CI build: compile → bundle .app → zip.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?Usage: build-release.sh <version>}"

swift build -c release --product UrBrowseApp
swift build -c release --product ur-browse

BIN_DIR=$(swift build -c release --show-bin-path)
APP_BIN="${BIN_DIR}/UrBrowseApp"
CLI_BIN="${BIN_DIR}/ur-browse"

# Diagnostics: print sizes so CI logs show what was actually built
echo "  UrBrowseApp: $(wc -c < "$APP_BIN" | tr -d ' ') bytes at $APP_BIN"
echo "  ur-browse:   $(wc -c < "$CLI_BIN" | tr -d ' ') bytes at $CLI_BIN"

# Sanity check: app binary must contain AppDelegate (only in the app target)
if ! nm "$APP_BIN" 2>/dev/null | grep -q "AppDelegate"; then
    echo "❌ $APP_BIN does not look like the app binary (no AppDelegate symbol)" >&2
    nm "$APP_BIN" 2>/dev/null | head -10 >&2
    exit 1
fi
echo "  ✓ app binary verified (AppDelegate present)"

bash scripts/bundle.sh "${BIN_DIR}" "${VERSION}"

ZIP="UrBrowse-v${VERSION}.zip"
rm -f "${ZIP}"
ditto -c -k --keepParent "urBrowse.app" "${ZIP}"
SHA=$(shasum -a 256 "${ZIP}" | awk '{print $1}')
echo "✓ ${ZIP}"
echo "  SHA256: ${SHA}"
