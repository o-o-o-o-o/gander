#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

SKIP_TESTS=false
OPEN_APP=false
SKIP_SMOKE=false

for arg in "$@"; do
    case "$arg" in
        --skip-tests)
            SKIP_TESTS=true
            ;;
        --open)
            OPEN_APP=true
            ;;
        --skip-smoke)
            SKIP_SMOKE=true
            ;;
        *)
            echo "Unknown option: $arg" >&2
            echo "Usage: bash publish.sh [--skip-tests] [--skip-smoke] [--open]" >&2
            exit 1
            ;;
    esac
done

echo "==> Debug build"
swift build

if [ "$SKIP_TESTS" = true ]; then
    echo "==> Tests skipped"
else
    echo "==> Running logic tests"
    bash logic-test.sh
fi

echo "==> Packaging Gander.app (local: $(pwd)/Gander.app)"
bash build.sh

if [ "$SKIP_SMOKE" = true ]; then
    echo "==> Smoke tests skipped"
else
    echo "==> Running smoke tests"
    bash smoke-test.sh
fi

if [ "$OPEN_APP" = true ]; then
    echo "==> Opening Gander.app"
    open Gander.app
fi

echo "==> Done"