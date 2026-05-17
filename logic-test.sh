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

        // ── canonicalURLString ────────────────────────────────────────────────
        expect(
            canonicalURLString("  HTTPS://Example.COM:443/docs  ") == "https://example.com/docs",
            "canonical URL: normalize scheme, host, strip default HTTPS port"
        )
        expect(
            canonicalURLString("https://github.com") == "https://github.com/",
            "canonical URL: add trailing slash for bare host"
        )
        expect(
            canonicalURLString("http://example.com:80/path") == "http://example.com/path",
            "canonical URL: strip default HTTP port 80"
        )
        expect(
            canonicalURLString("https://example.com:8080/path") == "https://example.com:8080/path",
            "canonical URL: preserve non-default port"
        )
        expect(
            canonicalURLString("https://example.com/search?q=swift") == "https://example.com/search?q=swift",
            "canonical URL: preserve query string"
        )
        expect(
            canonicalURLString("not a url") == "not a url",
            "canonical URL: return unmodified string when not parseable as URL"
        )

        // ── SiteConfig defaults and sanitizing ───────────────────────────────
        let decoded = try JSONDecoder().decode(
            SiteConfig.self,
            from: Data("{\"name\":\"Docs\",\"url\":\"https://example.com\"}".utf8)
        )
        expect(decoded.temporary == false, "SiteConfig: temporary should default to false")
        expect(decoded.shortcut == nil,    "SiteConfig: shortcut should default to nil")

        // shortcut: only 1–9 accepted; 0 and 10 are rejected
        let s0  = try JSONDecoder().decode(SiteConfig.self, from: Data("{\"name\":\"A\",\"url\":\"u\",\"shortcut\":0}".utf8))
        let s5  = try JSONDecoder().decode(SiteConfig.self, from: Data("{\"name\":\"A\",\"url\":\"u\",\"shortcut\":5}".utf8))
        let s9  = try JSONDecoder().decode(SiteConfig.self, from: Data("{\"name\":\"A\",\"url\":\"u\",\"shortcut\":9}".utf8))
        let s10 = try JSONDecoder().decode(SiteConfig.self, from: Data("{\"name\":\"A\",\"url\":\"u\",\"shortcut\":10}".utf8))
        expect(s0.shortcut  == nil, "SiteConfig: shortcut 0 should be sanitized to nil")
        expect(s5.shortcut  == 5,   "SiteConfig: shortcut 5 should be accepted")
        expect(s9.shortcut  == 9,   "SiteConfig: shortcut 9 should be accepted")
        expect(s10.shortcut == nil, "SiteConfig: shortcut 10 should be sanitized to nil")

        // ── AppConfig defaults ────────────────────────────────────────────────
        let defaults = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))
        expect(defaults.name           == "default",      "AppConfig: name defaults to 'default'")
        expect(defaults.width          == 420,            "AppConfig: width defaults to 420")
        expect(defaults.chrome         == true,           "AppConfig: chrome defaults to true")
        expect(defaults.stripeHeight   == 3,              "AppConfig: stripeHeight defaults to 3")
        expect(defaults.externalBrowser == "Safari",      "AppConfig: externalBrowser defaults to Safari")
        expect(defaults.color          == nil,            "AppConfig: color defaults to nil")
        expect(defaults.height         == nil,            "AppConfig: height defaults to nil (full screen)")
        expect(defaults.pinned         == nil,            "AppConfig: pinned defaults to nil")

        // ── pinned sanitizing: only "auto"/"manual" accepted ─────────────────
        let pAuto    = try JSONDecoder().decode(AppConfig.self, from: Data("{\"pinned\":\"auto\"}".utf8))
        let pManual  = try JSONDecoder().decode(AppConfig.self, from: Data("{\"pinned\":\"manual\"}".utf8))
        let pInvalid = try JSONDecoder().decode(AppConfig.self, from: Data("{\"pinned\":\"banana\"}".utf8))
        expect(pAuto.pinned    == "auto",   "AppConfig: pinned 'auto' should be accepted")
        expect(pManual.pinned  == "manual", "AppConfig: pinned 'manual' should be accepted")
        expect(pInvalid.pinned == nil,      "AppConfig: pinned 'banana' should be sanitized to nil")

        // ── HotkeysConfig: null/empty disables a hotkey ───────────────────────
        // A key set to null in JSON means "disabled" (nil). A missing key keeps its default.
        let hNull    = try JSONDecoder().decode(HotkeysConfig.self, from: Data("{\"toggle\":null}".utf8))
        let hEmpty   = try JSONDecoder().decode(HotkeysConfig.self, from: Data("{\"toggle\":\"\"}".utf8))
        let hMissing = try JSONDecoder().decode(HotkeysConfig.self, from: Data("{}".utf8))
        expect(hNull.toggle    == nil,             "HotkeysConfig: null toggle disables it")
        expect(hEmpty.toggle   == nil,             "HotkeysConfig: empty string toggle disables it")
        expect(hMissing.toggle == "cmd+shift+\\",  "HotkeysConfig: missing toggle keeps default")
        expect(hMissing.sites  == "cmd+shift+/",   "HotkeysConfig: missing sites keeps default")
        expect(hMissing.next   == "cmd+shift+]",   "HotkeysConfig: missing next keeps default")
        expect(hMissing.prev   == "cmd+shift+[",   "HotkeysConfig: missing prev keeps default")

        // ── NSColor hex parsing ───────────────────────────────────────────────
        expect(NSColor(hex: "#4A90D9") != nil, "NSColor: parse 6-digit hex with leading #")
        expect(NSColor(hex: "4A90D9")  != nil, "NSColor: parse 6-digit hex without #")
        expect(NSColor(hex: "ffffff")  != nil, "NSColor: parse lowercase hex")
        expect(NSColor(hex: "#gg0000") == nil, "NSColor: reject invalid hex digits")
        expect(NSColor(hex: "#abc")    == nil, "NSColor: reject 3-digit shorthand (not supported)")
        expect(NSColor(hex: "")        == nil, "NSColor: reject empty string")

        // ── notification name scoping ─────────────────────────────────────────
        let cfgDefault = AppConfig(name: "default")
        let cfgWork    = AppConfig(name: "work")
        expect(cfgDefault.notifToggle.rawValue == "com.gander.default.toggle",
               "notification names should be scoped to instance name")
        expect(cfgWork.notifToggle.rawValue == "com.gander.work.toggle",
               "different instances should have different notification names")
        expect(cfgDefault.notifToggle != cfgWork.notifToggle,
               "default and work toggle notifications must not collide")

        // ── FrameConfig.isEmpty ───────────────────────────────────────────────
        let emptyFrame = FrameConfig(x: nil, y: nil, width: nil, height: nil)
        let partialFrame = FrameConfig(x: 10, y: nil, width: nil, height: nil)
        expect(emptyFrame.isEmpty   == true,  "FrameConfig: all-nil is empty")
        expect(partialFrame.isEmpty == false, "FrameConfig: any non-nil is not empty")

        // ── initialFrame: configured values take precedence ───────────────────
        if let screen = NSScreen.main {
            let config = AppConfig(width: 460, height: 900, x: 55, y: 40)
            let frame = config.initialFrame(on: screen)
            expect(frame.origin.x    == 55,  "initialFrame: x should use configured value")
            expect(frame.origin.y    == 40,  "initialFrame: y should use configured value")
            expect(frame.size.width  == 460, "initialFrame: width should use configured value")
            expect(frame.size.height == 900, "initialFrame: height should use configured value")

            // When height is omitted the frame should fill the visible screen height
            let noHeight = AppConfig(width: 420)
            let autoFrame = noHeight.initialFrame(on: screen)
            expect(autoFrame.size.height == screen.visibleFrame.height,
                   "initialFrame: omitted height should fill visible screen height")
        }

        print("==> Logic tests passed")
    }
}
SWIFT

PROJECT_DIR="$(pwd)"
# Compile from TMP_DIR so swiftc's intermediate .o files go there, not the project root.
(cd "${TMP_DIR}" && swiftc "${PROJECT_DIR}/Sources/Gander/Config.swift" "${RUNNER}" -o "${BIN}")
"${BIN}"