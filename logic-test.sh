#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

TMP_DIR="$(mktemp -d /tmp/gander-logic.XXXXXX)"
RUNNER="${TMP_DIR}/logic-tests.swift"
BIN="${TMP_DIR}/gander-logic-tests"

cleanup() {
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

cat > "${RUNNER}" <<'SWIFT'
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
        expect(decoded.shortcut == nil, "shortcut should default to nil")

        // Shortcut sanitizing: only 1–9 accepted
        let s0  = try JSONDecoder().decode(SiteConfig.self, from: Data("{\"name\":\"A\",\"url\":\"u\",\"shortcut\":0}".utf8))
        let s5  = try JSONDecoder().decode(SiteConfig.self, from: Data("{\"name\":\"A\",\"url\":\"u\",\"shortcut\":5}".utf8))
        let s10 = try JSONDecoder().decode(SiteConfig.self, from: Data("{\"name\":\"A\",\"url\":\"u\",\"shortcut\":10}".utf8))
        expect(s0.shortcut  == nil, "shortcut 0 should be sanitized to nil")
        expect(s5.shortcut  == 5,   "shortcut 5 should be accepted")
        expect(s10.shortcut == nil, "shortcut 10 should be sanitized to nil")

        // Pinned sanitizing: only "auto"/"manual" accepted
        let pAuto    = try JSONDecoder().decode(AppConfig.self, from: Data("{\"pinned\":\"auto\"}".utf8))
        let pManual  = try JSONDecoder().decode(AppConfig.self, from: Data("{\"pinned\":\"manual\"}".utf8))
        let pInvalid = try JSONDecoder().decode(AppConfig.self, from: Data("{\"pinned\":\"banana\"}".utf8))
        let pNull    = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))
        expect(pAuto.pinned    == "auto",   "pinned 'auto' should be accepted")
        expect(pManual.pinned  == "manual", "pinned 'manual' should be accepted")
        expect(pInvalid.pinned == nil,      "pinned 'banana' should be sanitized to nil")
        expect(pNull.pinned    == nil,      "pinned absent should default to nil")

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

swiftc Sources/Gander/Config.swift "${RUNNER}" -o "${BIN}"
"${BIN}"