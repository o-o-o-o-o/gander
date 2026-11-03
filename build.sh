#!/bin/bash
# Local dev build → "./Ur Browse.app" (test-only; never copy over /Applications).
set -euo pipefail
cd "$(dirname "$0")"

# Version for Info.plist + Help (latest tag, or commit-ish dev label)
VERSION="$(git describe --tags --dirty 2>/dev/null | sed 's/^v//' || echo "dev")"

swift build -c release --product UrBrowseApp
swift build -c release --product ur-browse
bash scripts/bundle.sh "$(swift build -c release --show-bin-path)" "${VERSION}"
echo "  To test: open \"$(pwd)/Ur Browse.app\""
