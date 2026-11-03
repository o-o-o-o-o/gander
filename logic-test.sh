#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

TMP_DIR="$(mktemp -d /tmp/ur-browse-logic.XXXXXX)"
RUNNER="${TMP_DIR}/logic-tests.swift"
BIN="${TMP_DIR}/ur-browse-logic-tests"

cleanup() {
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

cat > "${RUNNER}" <<'SWIFT'
import AppKit
import Foundation

@main
struct LogicTests {
    // Takes a throwing autoclosure (like XCTAssert) so checks can call throwing parsers inline;
    // a thrown error counts as a failure.
    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) {
        let passed: Bool
        do { passed = try condition() } catch {
            fputs("logic test failed: \(message) (threw \(error))\n", stderr)
            exit(1)
        }
        if !passed {
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
        expect(defaults.stripeHeight   == 2,              "AppConfig: stripeHeight defaults to 2")
        expect(defaults.externalBrowser == "Safari",      "AppConfig: externalBrowser defaults to Safari")
        expect(defaults.glaze          == nil,            "AppConfig: glaze defaults to nil")
        expect(defaults.ephemeral      == false,          "AppConfig: ephemeral defaults to false")
        let legacyColor = try JSONDecoder().decode(AppConfig.self, from: Data("{\"color\":\"#2ECC71\"}".utf8))
        expect(legacyColor.glaze == "#2ECC71", "AppConfig: legacy 'color' is read as glaze")
        let bothColors = try JSONDecoder().decode(AppConfig.self, from: Data("{\"color\":\"#111111\",\"glaze\":\"#222222\"}".utf8))
        expect(bothColors.glaze == "#222222", "AppConfig: 'glaze' wins over 'color'")
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
        let pk = parseHotkey("cmd+shift+/")
        expect(pk?.keyCode == 44 && pk?.mods == [.command, .shift], "parseHotkey: cmd+shift+/")
        expect(parseHotkey("cmd+alt+x")?.mods == [.command, .option], "parseHotkey: alt is option")
        expect(parseHotkey(nil) == nil && parseHotkey("cmd+bogus") == nil, "parseHotkey: nil and unknown key")
        expect(parseHotkey("meta+shift+x") == nil, "parseHotkey: unknown modifier is rejected")
        expect(parseHotkey("space") == nil && parseHotkey("f") == nil, "parseHotkey: no modifier is rejected")

        // ── NSColor hex parsing ───────────────────────────────────────────────
        expect(NSColor(hex: "#4A90D9") != nil, "NSColor: parse 6-digit hex with leading #")
        expect(NSColor(hex: "4A90D9")  != nil, "NSColor: parse 6-digit hex without #")
        expect(NSColor(hex: "ffffff")  != nil, "NSColor: parse lowercase hex")
        expect(NSColor(hex: "#gg0000") == nil, "NSColor: reject invalid hex digits")
        expect(NSColor(hex: "#abc")    == nil, "NSColor: reject 3-digit shorthand (not supported)")
        expect(NSColor(hex: "")        == nil, "NSColor: reject empty string")

        // ── Pot names and paths ───────────────────────────────────────────────
        expect(Pot.isValidName("default") && Pot.isValidName("work-2") && Pot.isValidName("llm_x"),
               "Pot: plain names are valid")
        expect(!Pot.isValidName("") && !Pot.isValidName("-x") && !Pot.isValidName("a/b")
               && !Pot.isValidName("a b") && !Pot.isValidName(String(repeating: "a", count: 41)),
               "Pot: empty, leading dash, slash, space and over-long names are invalid")
        let workPot = Pot(app: "browse", name: "work")
        expect(workPot.configURL.path.hasSuffix("/browse/work/config.json"), "Pot: config path")
        expect(workPot.slipDirectory.path.hasSuffix("/browse/work/slip"), "Pot: slip path")
        expect(workPot.socketURL.lastPathComponent == "work.sock", "Pot: socket name")
        expect(workPot.launchAgentLabel == "io.ur.browse.work", "Pot: LaunchAgent label")
        expect(workPot.storageIdentifier == Pot(app: "browse", name: "work").storageIdentifier,
               "Pot: storage identifier is stable")
        expect(workPot.storageIdentifier != Pot(app: "browse", name: "default").storageIdentifier,
               "Pot: storage identifier differs per pot")

        // ── Request parsing (argv and URL share pot/verb rules) ───────────────
        let verbs = BrowseSpec.spec.allVerbs
        let r1 = try RequestParser.parse(argv: ["toggle"], verbs: verbs, defaultVerb: "toggle")
        expect(r1.pot == "default" && r1.verb == "toggle", "argv: bare verb → default pot")
        let r2 = try RequestParser.parse(argv: ["work", "open", "https://x.example", "--width", "400"],
                                         verbs: verbs, defaultVerb: "toggle")
        expect(r2.pot == "work" && r2.verb == "open" && r2.args == ["https://x.example"] && r2.options["width"] == "400",
               "argv: pot, verb, arg, option")
        let r3 = try RequestParser.parse(argv: ["work"], verbs: verbs, defaultVerb: "toggle")
        expect(r3.pot == "work" && r3.verb == "toggle", "argv: pot alone → default verb")
        let r4 = try RequestParser.parse(argv: ["sites", "--json", "--x=10"], verbs: verbs,
                                         booleanFlags: ["json"], defaultVerb: "toggle")
        expect(r4.options["json"] == "true" && r4.options["x"] == "10", "argv: boolean flag and --key=value")
        var threw = false
        do { _ = try RequestParser.parse(argv: ["show", "--width"], verbs: verbs, defaultVerb: "toggle") } catch { threw = true }
        expect(threw, "argv: option without value throws")

        let schemes = BrowseSpec.spec.schemes
        let u1 = RequestParser.parse(url: URL(string: "ur-browse://work/site/gh/o-o-o-o-o/ur-browse")!,
                                     schemes: schemes, verbs: verbs, defaultVerb: "toggle")
        expect(u1?.pot == "work" && u1?.verb == "site" && u1?.args == ["gh", "o-o-o-o-o", "ur-browse"],
               "url: pot/verb/args from host + path")
        let u2 = RequestParser.parse(url: URL(string: "gander://open?url=https%3A%2F%2Fexample.com&width=480")!,
                                     schemes: schemes, verbs: verbs, defaultVerb: "toggle")
        expect(u2?.pot == "default" && u2?.verb == "open" && u2?.options["url"] == "https://example.com"
               && u2?.options["width"] == "480", "url: legacy gander:// open with query")
        let u3 = RequestParser.parse(url: URL(string: "ur-browse://toggle")!, schemes: schemes, verbs: verbs, defaultVerb: "toggle")
        expect(u3?.pot == "default" && u3?.verb == "toggle", "url: bare verb host → default pot")
        expect(RequestParser.parse(url: URL(string: "https://example.com")!, schemes: schemes, verbs: verbs,
                                   defaultVerb: "toggle") == nil, "url: foreign scheme is nil")

        // ── BrowseCommand validation ──────────────────────────────────────────
        func cmd(_ argv: [String]) throws -> BrowseCommand {
            try BrowseCommand(RequestParser.parse(argv: argv, verbs: verbs, booleanFlags: ["list"], defaultVerb: "toggle"))
        }
        func fails(_ argv: [String]) -> Bool { (try? cmd(argv)) == nil }
        expect(try cmd(["open", "https://a.example", "--shortcut", "2"])
               == .open(url: "https://a.example", shortcut: 2, frame: FrameConfig()), "cmd: open with shortcut")
        expect(fails(["open"]), "cmd: open without URL fails")
        expect(fails(["open", "https://a.example", "--shortcut", "10"]), "cmd: shortcut out of range fails")
        expect(fails(["show", "--bogus", "1"]), "cmd: unknown option fails")
        expect(fails(["frame"]), "cmd: frame without preset or dimensions fails")
        expect(fails(["notacommand"]) , "cmd: unknown verb fails")
        expect(try cmd(["frame", "laptop"]) == .frame(FrameConfig(preset: "laptop")), "cmd: frame preset")
        expect(try cmd(["sites"]) == .picker, "cmd: bare sites toggles the picker (Gander compat)")
        expect(try cmd(["sites", "--list"]) == .listSites, "cmd: sites --list lists")
        var formatted = try RequestParser.parse(argv: ["sites"], verbs: verbs, defaultVerb: "toggle")
        formatted.options["format"] = "json"
        expect(try BrowseCommand(formatted) == .listSites, "cmd: sites with a format lists")
        expect(try cmd(["site", "gh/o-o-o-o-o/ur-browse"]) == .site(id: "gh", path: "o-o-o-o-o/ur-browse", frame: FrameConfig()),
               "cmd: site id/path from one CLI arg")
        expect(try BrowseCommand(u1!) == .site(id: "gh", path: "o-o-o-o-o/ur-browse", frame: FrameConfig()),
               "cmd: site id/path from URL segments")
        expect(try cmd(["site", "gh"]) == .site(id: "gh", path: nil, frame: FrameConfig()), "cmd: site without path")
        expect(fails(["site"]), "cmd: site without id fails")

        // ── SiteStore: ids, lookup, temporary sites, shortcuts ────────────────
        expect(SiteStore.slug("Hacker News") == "hacker-news", "slug: spaces → dash")
        expect(SiteStore.slug("  GitHub!! ") == "github", "slug: trims punctuation")
        expect(SiteStore.slug("🪿") == "site", "slug: nothing left → site")
        var store = SiteStore(sites: [
            SiteConfig(name: "GitHub", url: "https://github.com"),
            SiteConfig(id: "hn", name: "Hacker News", url: "https://news.ycombinator.com"),
            SiteConfig(name: "GitHub", url: "https://github.com/notifications"),
        ], pinned: "auto")
        expect(store.all.map { $0.id ?? "" } == ["github", "hn", "github-2"], "store: derived, explicit and de-duplicated ids")
        expect(store.site(id: "HN")?.name == "Hacker News", "store: id lookup is case-insensitive")
        expect(store.site(id: "hacker news")?.id == "hn", "store: name lookup")
        expect(store.site(id: "nope") == nil, "store: unknown id is nil")
        expect(store.site(forURL: "HTTPS://GitHub.com:443")?.id == "github", "store: canonical URL match")
        expect(store.site(matching: "https://github.com/?q=x")?.id == "github", "store: host+path match ignores query")
        let opened = store.siteForOpening(urlString: "https://example.org/docs")
        expect(opened.added && opened.site.temporary && opened.site.id == "example-org", "store: temporary site gets a host id")
        expect(store.siteForOpening(urlString: "https://example.org/docs").added == false, "store: temporary site is reused")
        expect(store.configShortcuts[2]?.id == "hn", "store: auto pinned shortcuts follow config order")
        store.setTransientShortcut(2, url: "https://example.org/docs")
        expect(store.shortcutURLMap()["https://example.org/docs"] == 2, "store: transient shortcut overrides")
        expect(store.site(forShortcut: 2)?.id == "example-org", "store: transient shortcut resolves")
        store.replaceConfigured([SiteConfig(name: "Example", url: "https://example.org/docs")])
        expect(store.all.count == 2 && store.all[1].id == "example-org", "store: temporary sites survive a sitesCommand refresh")
        expect(SiteStore.deepURL(base: "https://github.com/", path: "/o-o-o-o-o/ur-browse")
               == "https://github.com/o-o-o-o-o/ur-browse", "deepURL: joins with one slash")
        expect(SiteStore.deepURL(base: "https://x.example/search", path: "?q=a") == "https://x.example/search?q=a",
               "deepURL: query is appended as-is")
        let numericID = try JSONDecoder().decode(SiteConfig.self, from: Data("{\"id\":42,\"name\":\"A\",\"url\":\"u\"}".utf8))
        expect(numericID.id == "42", "SiteConfig: numeric id becomes a string")
        expect(BrowseAddress.site(pot: "work", id: "gh") == "ur-browse://work/site/gh", "address: site")

        // ── Slip ──────────────────────────────────────────────────────────────
        let slip = SlipScript.parse(file: "quiet.js", source: """
            // ==UserScript==
            // @name   Quiet GitHub
            // @match  *://*.github.com/*
            // @exclude https://github.com/settings/*
            // @run-at document-start
            // ==/UserScript==
            document.title = 'x';
            """)!
        expect(slip.name == "Quiet GitHub" && slip.runAt == .documentStart && slip.kind == .js, "slip: header parsed")
        expect(slip.applies(to: "https://github.com/o-o-o-o-o"), "slip: *. matches the bare domain")
        expect(slip.applies(to: "https://gist.github.com/x"), "slip: *. matches a subdomain")
        expect(!slip.applies(to: "https://github.com/settings/profile"), "slip: exclude wins")
        expect(!slip.applies(to: "https://notgithub.com/"), "slip: other hosts do not match")
        let css = SlipScript.parse(file: "dark.css", source: "body { background: #000 }")!
        expect(css.kind == .css && css.runAt == .documentStart && css.applies(to: "https://any.example/"),
               "slip: css defaults to every page at document start")
        expect(SlipScript.parse(file: "notes.md", source: "x") == nil, "slip: other extensions are ignored")
        expect(css.wrappedSource().contains("data-slip"), "slip: css is wrapped in a style injector")

        // ── FrameConfig.isEmpty ───────────────────────────────────────────────
        let emptyFrame = FrameConfig(preset: nil, x: nil, y: nil, width: nil, height: nil)
        let presetFrame = FrameConfig(preset: "laptop", x: nil, y: nil, width: nil, height: nil)
        expect(emptyFrame.isEmpty    == true,  "FrameConfig: all-nil is empty")
        expect(presetFrame.isEmpty   == false, "FrameConfig: preset name is not empty")

        // ── FrameDimension / FrameAxis parsing ────────────────────────────────
        expect(FrameDimension.parse("100%") == .percent(100), "parse 100%")
        expect(FrameDimension.parse("full") == .percent(100), "parse full")
        expect(FrameDimension.parse("420") == .points(420), "parse points")
        expect(FrameAxis.parse("right") == .right, "parse right anchor")
        expect(FrameAxis.parse("bottom") == .bottom, "parse bottom anchor")

        let visible = CGRect(x: 100, y: 50, width: 1600, height: 900)
        let laptopPreset = FramePreset(
            width: .percent(30),
            height: .percent(100),
            x: .right,
            y: .bottom
        )
        let resolved = FrameResolver.computedRect(laptopPreset, visible: visible, fallbackWidth: 420)
        expect(resolved.width == 480, "30% width of 1600")
        expect(resolved.height == 900, "100% height")
        expect(resolved.maxX == visible.maxX, "right anchor")
        expect(resolved.minY == visible.minY, "bottom anchor")

        // ── frameAuto matching ────────────────────────────────────────────────
        let auto = FrameAutoConfig(match: [
            FrameAutoMatch(screenCount: 1, screenCountMin: nil, frame: "laptop"),
            FrameAutoMatch(screenCount: nil, screenCountMin: 2, frame: "studio"),
        ])
        expect(auto.presetName(forScreenCount: 1) == "laptop", "auto: one screen → laptop")
        expect(auto.presetName(forScreenCount: 2) == "studio", "auto: two screens → studio")

        // ── initialFrame: legacy root fields ──────────────────────────────────
        if let screen = NSScreen.main {
            let config = AppConfig(width: 460, height: 900, x: 55, y: 40)
            let expected = FrameResolver.computedRect(config.legacyDefaultPreset(),
                                                      on: screen, fallbackWidth: 460)
            let frame = config.initialFrame(on: screen)
            expect(frame == expected, "initialFrame: legacy root fields match resolved preset")

            let noHeight = AppConfig(width: 420)
            let autoFrame = noHeight.initialFrame(on: screen)
            expect(autoFrame.size.height == screen.visibleFrame.height,
                   "initialFrame: omitted height should fill visible screen height")

            let named = AppConfig(
                frames: [
                    "laptop": FramePreset(width: .points(360), height: .percent(100), x: .right, y: .bottom),
                ],
                frameAuto: FrameAutoConfig(match: [
                    FrameAutoMatch(screenCount: nil, screenCountMin: 1, frame: "laptop"),
                ])
            )
            expect(named.launchPresetName(screenCount: 1) == "laptop",
                   "launch preset from frameAuto")
            let namedFrame = named.initialFrame(on: screen)
            expect(namedFrame.size.width == 360, "named preset width")
        }

        // ── sitesCommand ──────────────────────────────────────────────────────
        expect(defaults.sitesCommand == nil, "AppConfig: sitesCommand defaults to nil")
        let withCmd = try JSONDecoder().decode(AppConfig.self, from: Data("{\"sitesCommand\":\"echo []\"}".utf8))
        expect(withCmd.sitesCommand == "echo []", "AppConfig: sitesCommand decodes")
        let emptyCmd = try JSONDecoder().decode(AppConfig.self, from: Data("{\"sitesCommand\":\"\"}".utf8))
        expect(emptyCmd.sitesCommand == nil, "AppConfig: empty sitesCommand is nil")

        // listBookmarks shape: extra keys ignored, entries without url skipped
        let parsed = AppConfig.parseSites(Data("""
            [{"uuid":"U","tags":"t","name":"Claude","url":"https://claude.ai/new","aliases":""},
             {"name":"no url"}]
            """.utf8))
        expect(parsed?.count == 1 && parsed?[0].name == "Claude", "parseSites: keeps valid entries only")
        expect(AppConfig.parseSites(Data("[]".utf8)) == nil, "parseSites: empty array is nil")
        expect(AppConfig.parseSites(Data("not json".utf8)) == nil, "parseSites: non-JSON is nil")
        expect(AppConfig.parseSites(Data("{\"name\":\"A\",\"url\":\"u\"}".utf8)) == nil, "parseSites: object is nil")

        let ran = AppConfig.runSitesCommand("echo noise >&2; echo '[{\"name\":\"A\",\"url\":\"https://a.example\"}]'")
        expect(ran?.first?.url == "https://a.example", "runSitesCommand: parses stdout, ignores stderr")
        expect(AppConfig.runSitesCommand("echo '[{\"name\":\"A\",\"url\":\"u\"}]'; exit 3") == nil,
               "runSitesCommand: non-zero exit is nil")
        expect(AppConfig.runSitesCommand("sleep 5", timeout: 0.5) == nil, "runSitesCommand: timeout is nil")
        // A background grandchild keeps the pipe open after zsh exits: must still time out.
        let started = Date()
        expect(AppConfig.runSitesCommand("(sleep 4; echo '[]') &", timeout: 0.5) == nil,
               "runSitesCommand: grandchild holding the pipe is nil")
        expect(Date().timeIntervalSince(started) < 2, "runSitesCommand: grandchild does not block past timeout")

        print("==> Logic tests passed")
    }
}
SWIFT

PROJECT_DIR="$(pwd)"
# Compile from TMP_DIR so swiftc's intermediate .o files go there, not the project root.
# Everything below compiles into ONE module, so the UrKit / UrBrowseSpec sources are listed
# directly; their `import UrKit` lines are wrapped in `#if canImport(UrKit)` for this reason.
(cd "${TMP_DIR}" && swiftc \
    "${PROJECT_DIR}"/Sources/UrKit/*.swift \
    "${PROJECT_DIR}/Sources/UrBrowseSpec/BrowseSpec.swift" \
    "${PROJECT_DIR}/Sources/UrBrowse/Config.swift" \
    "${PROJECT_DIR}/Sources/UrBrowse/FrameLayout.swift" \
    "${PROJECT_DIR}/Sources/UrBrowse/SiteStore.swift" \
    "${PROJECT_DIR}/Sources/UrBrowse/BrowseCommand.swift" \
    "${PROJECT_DIR}/Sources/UrBrowse/Slip.swift" \
    "${PROJECT_DIR}/Sources/UrBrowse/Replies.swift" \
    "${RUNNER}" -o "${BIN}")
"${BIN}"