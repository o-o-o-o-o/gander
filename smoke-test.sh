#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

INSTANCE_NAME="smoke-${RANDOM}-${RANDOM}"
TMP_DIR="$(mktemp -d /tmp/gander-smoke.XXXXXX)"
CONFIG_PATH="${TMP_DIR}/${INSTANCE_NAME}.json"
APP_PID=""
FAILED=0

cleanup() {
    if [[ -n "${APP_PID}" ]] && kill -0 "${APP_PID}" 2>/dev/null; then
        kill "${APP_PID}" 2>/dev/null || true
        wait "${APP_PID}" 2>/dev/null || true
    fi
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

cat > "${CONFIG_PATH}" <<EOF
{
  "name": "${INSTANCE_NAME}",
  "width": 360,
  "height": 720,
  "x": 20,
  "y": 20,
  "defaultUrl": "https://example.com",
  "sites": [
    { "name": "Example", "url": "https://example.com" },
    { "name": "GitHub",  "url": "https://github.com" }
  ]
}
EOF

if [[ ! -x ".build/release/GanderApp" ]]; then
    echo "Missing .build/release/GanderApp; run bash build.sh first" >&2
    exit 1
fi

if [[ ! -x ".build/release/gander" ]]; then
    echo "Missing .build/release/gander; run bash build.sh first" >&2
    exit 1
fi

CLI=".build/release/gander"

# Run a CLI command and verify the app is still alive afterward.
cmd() {
    local label="$1"; shift
    "${CLI}" "$@"
    if ! kill -0 "${APP_PID}" 2>/dev/null; then
        echo "  ✗ ${label} — app crashed" >&2
        cat /tmp/gander-smoke.log >&2 || true
        FAILED=1
        return 1
    fi
    echo "  ✓ ${label}"
}

# Assert that a CLI invocation exits non-zero (for error-path testing).
cmd_fails() {
    local label="$1"; shift
    if "${CLI}" "$@" 2>/dev/null; then
        echo "  ✗ ${label} — expected non-zero exit" >&2
        FAILED=1
    else
        echo "  ✓ ${label}"
    fi
}

echo "==> Launching isolated smoke instance: ${INSTANCE_NAME}"
.build/release/GanderApp --config "${CONFIG_PATH}" >/tmp/gander-smoke.log 2>&1 &
APP_PID=$!

# Wait up to 4 seconds for the app to start
for _ in {1..20}; do
    if kill -0 "${APP_PID}" 2>/dev/null; then break; fi
    sleep 0.2
done

if ! kill -0 "${APP_PID}" 2>/dev/null; then
    echo "Smoke instance failed to start" >&2
    cat /tmp/gander-smoke.log >&2 || true
    exit 1
fi

echo "==> Exercising show/hide/toggle"
cmd "show with frame"  "${INSTANCE_NAME}" show --width 380 --height 680 --x 30 --y 30
cmd "hide"             "${INSTANCE_NAME}" hide
cmd "toggle (show)"    "${INSTANCE_NAME}" toggle
cmd "toggle (hide)"    "${INSTANCE_NAME}" toggle

echo "==> Exercising open and frame"
cmd "open URL"                   "${INSTANCE_NAME}" open https://github.com --width 400
cmd "open transient URL"         "${INSTANCE_NAME}" open https://example.org/temporary
cmd "open with shortcut"         "${INSTANCE_NAME}" open https://github.com --shortcut 1
cmd "open with shortcut + frame" "${INSTANCE_NAME}" open https://github.com --shortcut 2 --width 390
cmd "frame only"                 "${INSTANCE_NAME}" frame --x 40 --y 40 --width 390 --height 650

echo "==> Exercising site navigation"
cmd "next"  "${INSTANCE_NAME}" next
cmd "prev"  "${INSTANCE_NAME}" prev
cmd "sites" "${INSTANCE_NAME}" sites

echo "==> Exercising menu bar restore"
cmd "menubar" "${INSTANCE_NAME}" menubar

echo "==> Final hide"
cmd "hide" "${INSTANCE_NAME}" hide

echo "==> Checking CLI error handling"
cmd_fails "unknown command exits non-zero"       "${INSTANCE_NAME}" notacommand
cmd_fails "frame with no args exits non-zero"    "${INSTANCE_NAME}" frame
cmd_fails "open with no URL exits non-zero"      "${INSTANCE_NAME}" open
cmd_fails "unknown option exits non-zero"        "${INSTANCE_NAME}" show --bogus 99
cmd_fails "shortcut out of range exits non-zero" "${INSTANCE_NAME}" open https://example.com --shortcut 10

echo "==> Checking bundle assets"
if [[ ! -f "Gander.app/Contents/Resources/greg.png" ]]; then
    echo "  ✗ expected processed menubar icon inside app bundle" >&2
    FAILED=1
else
    echo "  ✓ menubar icon present in bundle"
fi

if [[ "${FAILED}" -ne 0 ]]; then
    echo "==> Smoke test FAILED" >&2
    exit 1
fi
echo "==> Smoke test passed"
