#!/bin/bash
# Cut a new release: tag, push tag, trigger GitHub Actions build.
#
# Usage:
#   bash scripts/release.sh 0.2.0
#
set -euo pipefail

VERSION="${1:?Usage: release.sh <version>  (e.g. 0.2.0)}"
VERSION="${VERSION#v}"   # strip leading 'v' so both '0.2.0' and 'v0.2.0' work
TAG="v${VERSION}"

if git rev-parse "${TAG}" >/dev/null 2>&1; then
    echo "Tag ${TAG} already exists" >&2
    exit 1
fi

dirty="$(git status --porcelain)"
if [[ -n "${dirty}" ]]; then
    echo "Working tree is dirty — commit or stash changes first" >&2
    exit 1
fi

echo "==> Running logic tests"
bash "$(dirname "$0")/../logic-test.sh"

echo "==> Pushing main"
git push origin main

echo "==> Tagging ${TAG}"
git tag "${TAG}"

echo "==> Pushing tag to origin"
git push origin "${TAG}"

echo ""
echo "✓ Release ${TAG} triggered."
echo "  Watch it at: https://github.com/o-o-o-o-o/gander/actions"
echo "  Release will appear at: https://github.com/o-o-o-o-o/gander/releases/tag/${TAG}"
