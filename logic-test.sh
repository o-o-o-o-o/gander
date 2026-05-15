#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

TMP_DIR="$(mktemp -d /tmp/gander-logic.XXXXXX)"
RUNNER="$TMP_DIR/logic-tests.swift"
BIN="$TMP_DIR/gander-logic-tests"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat > "$RUNNER" <<'SWIFT'
import AppKit
import Foundation

@main
struct LogicTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("logic test failed: \(message)\n", stderr)
            exit(1)
        }
    }

    static func main() throws {
        expect(
            canonicalURLString("  HTTPS://Example.COM:443/docs  ") == "https://example.com/docs",
            "canonical URL should normalize scheme, host, and default port"
        )

        expect(
            canonicalURLString("https://github.com") == "https://github.com/",
            "canonical URL should add a trailing slash for a bare host"
        )

        let decoded = try JSONDecoder().decode(
            SiteConfig.self,
            from: Data("{\"name\":\"Docs\",\"url\":\"https://example.com\"}".utf8)
        )
        expect(decoded.temporary == false, "temporary should default to false")

        if let screen = NSScreen.main {
            let config = AppConfig(width: 460, height: 900, x: 55, y: 40)
            let frame = config.initialFrame(on: screen)
            expect(frame.origin.x == 55, "frame x should use configured value")
            expect(frame.origin.y == 40, "frame y should use configured value")
            expect(frame.size.width == 460, "frame width should use configured value")
            expect(frame.size.height == 900, "frame height should use configured value")
        }

        print("==> Logic tests passed")
    }
}
SWIFT

swiftc Sources/Gander/Config.swift "$RUNNER" -o "$BIN"
"$BIN"