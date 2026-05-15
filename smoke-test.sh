#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

INSTANCE_NAME="smoke-$RANDOM-$RANDOM"
TMP_DIR="$(mktemp -d /tmp/gander-smoke.XXXXXX)"
CONFIG_PATH="$TMP_DIR/$INSTANCE_NAME.json"
APP_PID=""

cleanup() {
    if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
        kill "$APP_PID" 2>/dev/null || true
        wait "$APP_PID" 2>/dev/null || true
    fi
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat > "$CONFIG_PATH" <<EOF
{
  "name": "$INSTANCE_NAME",
  "width": 360,
  "height": 720,
  "x": 20,
  "y": 20,
  "defaultUrl": "https://example.com",
  "sites": [
    { "name": "Example", "url": "https://example.com" },
    { "name": "GitHub", "url": "https://github.com" }
  ]
}
EOF

if [ ! -x ".build/release/GanderApp" ]; then
    echo "Missing .build/release/GanderApp; run bash build.sh first" >&2
    exit 1
fi

if [ ! -x ".build/release/gander" ]; then
    echo "Missing .build/release/gander; run bash build.sh first" >&2
    exit 1
fi

echo "==> Launching isolated smoke instance: $INSTANCE_NAME"
.build/release/GanderApp --config "$CONFIG_PATH" >/tmp/gander-smoke.log 2>&1 &
APP_PID=$!

for _ in {1..20}; do
    if kill -0 "$APP_PID" 2>/dev/null; then
        break
    fi
    sleep 0.2
done

if ! kill -0 "$APP_PID" 2>/dev/null; then
    echo "Smoke instance failed to start" >&2
    cat /tmp/gander-smoke.log >&2 || true
    exit 1
fi

echo "==> Exercising CLI commands"
.build/release/gander "$INSTANCE_NAME" show --width 380 --height 680 --x 30 --y 30
.build/release/gander "$INSTANCE_NAME" open https://github.com --width 400
.build/release/gander "$INSTANCE_NAME" open https://example.org/temporary --height 640
.build/release/gander "$INSTANCE_NAME" frame --x 40 --y 40 --width 390 --height 650
.build/release/gander "$INSTANCE_NAME" next
.build/release/gander "$INSTANCE_NAME" prev
.build/release/gander "$INSTANCE_NAME" hide

if ! kill -0 "$APP_PID" 2>/dev/null; then
    echo "Smoke instance exited unexpectedly during CLI exercise" >&2
    cat /tmp/gander-smoke.log >&2 || true
    exit 1
fi

if [ ! -f "Gander.app/Contents/Resources/greg.png" ]; then
    echo "Expected processed menubar icon inside app bundle" >&2
    exit 1
fi

echo "==> Smoke test passed"