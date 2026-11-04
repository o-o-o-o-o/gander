#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

INSTANCE_NAME="smoke-${RANDOM}-${RANDOM}"
TMP_DIR="$(mktemp -d /tmp/ur-browse-smoke.XXXXXX)"
CONFIG_PATH="${TMP_DIR}/${INSTANCE_NAME}.json"
APP_PID=""
FAILED=0

# Fully isolated pot: config/slip folder and socket live in TMP_DIR, never in ~/.config/ur or
# ~/Library. Both the app and the CLI read these, so they agree on where the socket is.
export UR_CONFIG_HOME="${TMP_DIR}/config"
export UR_RUN_DIR="${TMP_DIR}/run"
mkdir -p "${UR_CONFIG_HOME}/browse/${INSTANCE_NAME}/slip"
cat > "${UR_CONFIG_HOME}/browse/${INSTANCE_NAME}/slip/smoke.js" <<'JS'
// @match https://example.com/*
document.documentElement.dataset.slip = "smoke";
JS

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
  "ephemeral": true,
  "sites": [
    { "name": "Example", "url": "https://example.com" },
    { "id": "gh", "name": "GitHub",  "url": "https://github.com" }
  ]
}
EOF

if [[ ! -x ".build/release/UrBrowseApp" ]]; then
    echo "Missing .build/release/UrBrowseApp; run bash build.sh first" >&2
    exit 1
fi

if [[ ! -x ".build/release/ur-browse" ]]; then
    echo "Missing .build/release/ur-browse; run bash build.sh first" >&2
    exit 1
fi

CLI=".build/release/ur-browse"

# Run a CLI command and verify the app is still alive afterward.
cmd() {
    local label="$1"; shift
    "${CLI}" "$@"
    if ! kill -0 "${APP_PID}" 2>/dev/null; then
        echo "  ✗ ${label} — app crashed" >&2
        cat /tmp/ur-browse-smoke.log >&2 || true
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
.build/release/UrBrowseApp --config "${CONFIG_PATH}" >/tmp/ur-browse-smoke.log 2>&1 &
APP_PID=$!

# Wait up to 8 seconds for the pot to answer on its socket
READY=0
for _ in {1..40}; do
    if ! kill -0 "${APP_PID}" 2>/dev/null; then break; fi
    if "${CLI}" "${INSTANCE_NAME}" info >/dev/null 2>&1; then READY=1; break; fi
    sleep 0.2
done

if [[ "${READY}" -ne 1 ]]; then
    echo "Smoke pot failed to start (no answer on ${UR_RUN_DIR}/browse/${INSTANCE_NAME}.sock)" >&2
    cat /tmp/ur-browse-smoke.log >&2 || true
    exit 1
fi

# Assert that a CLI invocation succeeds and its stdout contains a string.
cmd_prints() {
    local label="$1"; local needle="$2"; shift 2
    local out
    if ! out="$("${CLI}" "$@" 2>&1)"; then
        echo "  ✗ ${label} — exited non-zero: ${out}" >&2
        FAILED=1
    elif [[ "${out}" != *"${needle}"* ]]; then
        echo "  ✗ ${label} — expected '${needle}' in: ${out}" >&2
        FAILED=1
    else
        echo "  ✓ ${label}"
    fi
}

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

echo "==> Exercising addressable sites"
cmd_prints "sites --json lists ids"     '"id" : "gh"'           "${INSTANCE_NAME}" sites --json
cmd_prints "sites --json has addresses" "ur-browse://${INSTANCE_NAME}/site/gh" "${INSTANCE_NAME}" sites --json
cmd_prints "sites --alfred items"       '"items"'               "${INSTANCE_NAME}" sites --alfred
cmd_prints "site by derived id"         "Example"               "${INSTANCE_NAME}" site example
cmd_prints "site deep link"             "GitHub"                "${INSTANCE_NAME}" site gh/o-o-o-o-o
cmd_prints "current --json"             '"site" : "gh"'         "${INSTANCE_NAME}" current --json
cmd_prints "info --json"                "\"pot\" : \"${INSTANCE_NAME}\"" "${INSTANCE_NAME}" info --json
cmd_prints "slip --list"                "smoke.js"              "${INSTANCE_NAME}" slip --list
cmd_prints "slip reload"                "smoke.js"              "${INSTANCE_NAME}" slip
cmd_prints "pots lists the smoke pot"   "${INSTANCE_NAME}"      pots

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
cmd_fails "unknown site id exits non-zero"       "${INSTANCE_NAME}" site no-such-site
cmd_fails "stopped pot exits non-zero"           "not-running-${RANDOM}" hide

echo "==> Checking duplicate pot launch steps aside"
.build/release/UrBrowseApp --config "${CONFIG_PATH}" >/dev/null 2>&1 &
DUP_PID=$!
for _ in {1..25}; do kill -0 "${DUP_PID}" 2>/dev/null || break; sleep 0.2; done
if kill -0 "${DUP_PID}" 2>/dev/null; then
    kill "${DUP_PID}" 2>/dev/null || true
    echo "  ✗ second copy of the pot kept running" >&2
    FAILED=1
else
    echo "  ✓ second copy exited"
fi
cmd "original pot still answers" "${INSTANCE_NAME}" hide

echo "==> Checking bundle assets"
if [[ ! -f "ur-Browse.app/Contents/Resources/greg.png" ]]; then
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
