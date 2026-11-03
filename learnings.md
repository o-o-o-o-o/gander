# Ur Browse (Gander) — Project Learnings

Everything discovered while building and iterating on Ur Browse, formerly Gander. Organized for
fast re-onboarding and to avoid repeating the same mistakes. Sections written before the rename
(2026-11-03) still say "Gander", "instance", `gander://` and `DistributedNotificationCenter`;
read those as history. Where the design changed, the old section is marked *superseded* and a
newer section follows.

*Note: this is a first Swift/macOS native app. The "AppKit Fundamentals" section below captures
patterns that experienced AppKit developers take for granted but that are non-obvious when
coming from other platforms.*

---

## What Ur Browse Is

A floating sidebar browser for macOS 14+ — an `NSPanel` containing a `WKWebView` that stays
visible across all Mission Control spaces and Aerospace window-manager spaces. It is the first app
of the **Ur** suite (ur-mail and ur-notes will follow), nicknamed Gander (the goose icon stays).
App `Ur Browse.app`, CLI `ur-browse` (legacy alias `gander`), URL schemes `ur-browse://` and legacy
`gander://`, bundle id `io.ur.browse`. The CLI, the URL scheme and the hotkeys all feed the same
request dispatcher in the app; the CLI and the app talk over a per-pot Unix socket.

### Lexicon

- **Ur** — the suite; address scheme `<app>://<pot>/<kind>/<id>`
- **clay** — the app template / source (UrKit + `UrAppSpec`)
- **pot** — an instance: own config, slip scripts, website data store, socket, optional LaunchAgent
- **throw** — create a pot; **glaze** — a pot's look (`glaze` config key); **slip** — user scripts
  and styles; **kiln** — build / test / promote (`publish.sh`)

---

## Architecture

```
Package.swift            products: UrKit (library), UrBrowseApp, ur-browse (CLI)
Sources/UrKit/           Foundation-only, shared by every Ur app
  Pot.swift                config / slip / socket / LaunchAgent paths, name rules, storage UUID
  Request.swift Response.swift  one addressed command shape from argv, URLs and the wire
  IPC.swift                Unix-socket server + client (request/reply)
  CLI.swift                UrAppSpec + UrCLI: pots / throw / start / help, --json / --alfred,
                           autostart, Alfred Script Filter output
Sources/UrBrowseSpec/BrowseSpec.swift   the verb list, usage text and UrAppSpec for Ur Browse
Sources/UrBrowse/        the app (target UrBrowseApp)
  main.swift               launch forms (--pot, --config), pot folder, migration from
                           ~/.config/gander/<name>.json
  AppDelegate.swift        socket server, URL scheme (NSAppleEventManager) + forwarding,
                           one dispatcher for socket and URL requests, menu bar, help panel
  BrowseCommand.swift      typed verbs + the single validator
  SidebarPanel.swift       NSPanel subclass: WKWebView session pool, keyboard shortcuts,
                           external browser, frame control
  SiteStore.swift         site list, ids, URL matching, temporary sites, shortcuts (pure logic)
  Slip.swift              user scripts / styles (pure parsing + wrapping)
  Replies.swift           Encodable payloads behind --json
  FrameLayout.swift  SitePicker.swift  FindBar.swift  Config.swift  HelpContent.swift
Sources/ur-browse-cli/main.swift   `UrCLI(BrowseSpec.spec).run()`
scripts/bundle.sh        assembles "Ur Browse.app"; used by build.sh and scripts/build-release.sh
```

Adding a verb = `BrowseSpec.verbs` + `BrowseCommand` + `AppDelegate.execute`, nothing else.

---

## Key Design Decisions (and Why)

### NSPanel, not NSWindow

`NSPanel` with:
```swift
collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
level = .floating
isFloatingPanel = true
hidesOnDeactivate = false
```
This makes the sidebar float above all other windows on every Space, including Aerospace virtual
desktops. `hidesOnDeactivate = false` means it stays visible when you switch to another app.
Without `isFloatingPanel = true` some window managers pull it off the floating level.

### `canBecomeKey: Bool { true }` override — do not remove

`NSPanel` with `.nonactivatingPanel` can only become key (receive keyboard events) if it has
`.titled` or an `NSToolbar`. In `chrome: false` mode, both are stripped. Without the override:
- `makeKeyAndOrderFront` silently does nothing
- keyboard events are never delivered to the panel
- `WKWebView` cursor-change tracking breaks
- `makeFirstResponder(pickerView.searchField)` fails silently

This burned us when `chrome: false` was introduced and removed `.titled` and the toolbar —
everything stopped working with no error message. The fix is one line.

Added `canBecomeMain: Bool { false }` alongside it (2026-09-30, found via driceroland/Search,
`Float.swift`): the panel takes keyboard focus without also claiming "main window" status from
the app's real window. Gander has no other window today, so this is a no-op in practice, but
it's the correct pairing if a second window (preferences, etc.) is ever added.

### Copy/paste in a non-activating accessory app

⌘C/⌘V did nothing because Gander never becomes the active app (`.nonactivatingPanel` +
`.accessory`), so the frontmost app's menu bar kept those shortcuts. Two pieces fix it without
activating Gander or stealing focus from the user's main app:

1. **Hidden `NSApp.mainMenu` Edit submenu** — standard pattern for menu-bar-only apps; wires
   key equivalents into the responder chain when they do reach Gander.
2. **Local key monitor in `SidebarPanel`** — when `isKeyWindow`, intercept ⌘C/⌘V/⌘X/⌘A and
   `NSApp.sendAction(..., to: nil, from: event)` so they hit `WKWebView` or the site picker's
   search field even while another app stays active.

Do not call `NSApp.activate` on click — that would break the sidebar-over-IDE workflow.

**1Password direct paste:** 1Password tags copied passwords with `org.nspasteboard.ConcealedType` /
`com.agilebits.onepassword`. WKWebView refuses that pasteboard shape; pasting into TextEdit first
strips the markers. Fix: on ⌘V when those types are present, read plain `NSString`, trim trailing
newlines (common 1Password gotcha — causes "invalid login" while the field looks correct), rewrite
the pasteboard without concealed types, then call normal `paste:`. JS inject is fallback only.

**Login "invalid" in WKWebView:** If typing manually also fails in Safari but works in Chrome, it's
the site. If it works in Safari but not Gander, check Safari-like `customUserAgent` and that
`activeWebView` is first responder (`show` / `becomeKey`). Google/Facebook/Apple OAuth often block
all embedded webviews — use "Open in browser" (⌘⇧O) for those.

**Safari Web Inspector for Gander:** WKWebView does not appear under Develop until `isInspectable = true`
(macOS 13.3+, set in `makeWebView()` / Help panel). Quit and relaunch after rebuilding; panel must
be open with a page loaded. Safari → Settings → Advanced → “Show features for web developers”.

**⌘⇧O did nothing:** `charactersIgnoringModifiers` is `"O"` with Shift held, not `"o"`. Compare with
`lowercased()`. Default `externalBrowser: "Safari"` is an app name, not bundle ID — resolve via
`com.apple.Safari` or `/Applications/Safari.app`.

### Carbon `RegisterEventHotKey` for global hotkeys (superseded 2026-10-28 — see TASK-5)

Alternatives considered: `CGEventTap` (requires Input Monitoring TCC permission, user dialog),
`NSEvent.addGlobalMonitorForEvents` (same permission), `MASShortcut` (external dependency).

Carbon `RegisterEventHotKey`:
- No Input Monitoring permission, no TCC dialog, no user friction
- System-wide from the moment the app launches
- Works in all macOS versions that support the Carbon Events framework
- Tradeoff: can't suppress the keypress — it still propagates to the frontmost app

The signature `0x47414E44` is the ASCII encoding of `GAND` — a stable 4-byte app identifier
required by the Carbon API. Arbitrary but must be unique per app.

### NSDistributedNotificationCenter for IPC (superseded 2026-11-03 — see "Socket IPC replaces DistributedNotificationCenter")

*History. Gander only; Ur Browse uses a Unix socket.*

The CLI posts a named notification; the app observes it. No XPC, no sockets, no pipes, no
service registration, no entitlements.

Notification names are scoped to the instance name so multiple instances coexist without
interference: `com.gander.<name>.toggle`, `com.gander.<name>.open`, etc.

**Incompatible with App Sandbox** — if ever distributing via Mac App Store this would need
replacement. Fine for direct/Cask distribution.

The CLI ends with `Thread.sleep(forTimeInterval: 0.15)` because notification delivery is async
and the process must stay alive long enough for the OS to route it before `exit(0)` fires.

### No Xcode project

`swift build -c release` + manual `.app` bundle assembly in `build-release.sh`. No `.xcodeproj`,
no provisioning profiles, no Xcode required.

- Any machine with Xcode Command Line Tools (not full Xcode) can build
- No Apple Developer account required — distributed unsigned via Homebrew Cask
- The entire build is auditable shell + Swift, nothing hidden in Xcode's project format

### One WKWebView per site (session pool)

`sessions: [String: WKWebView]` in `SidebarPanel` keeps a live `WKWebView` per canonical URL.
Switching sites just swaps which one is in the view hierarchy. Sessions (cookies, JS state,
scroll position) survive site switches and app hide/show cycles.

Tradeoff: each `WKWebView` spawns its own Web Content process. With 5–10 sites this is fine;
with 50 it would be wasteful.

### Canonical URL as session key

`canonicalURLString` normalizes scheme (lowercase), host (lowercase), strips default ports
(443 for https, 80 for http), and adds a trailing slash for bare hosts. This prevents duplicate
sessions for `https://github.com` vs `https://GitHub.com/` vs `https://github.com:443/`.

### Multiple instances (superseded 2026-11-03 — see "Pots and per-pot WKWebsiteDataStore")

*History: these are now called pots; most of the rules below changed.*

Each instance is a separate process launched with `GanderApp --config <path>`. The `name` field
in the config drives:
- All `DistributedNotificationCenter` notification names
- The `UserDefaults` key for the "hide menu bar icon" preference
- The `gander <name> <command>` CLI routing
- The `gander://<name>/action` URL scheme routing

No inter-instance coordination. Each instance is completely independent.

Second-instance rules (found 2026-10-14 when the `llm` instance replaced the BTT hotkey window):
- (Superseded by TASK-5: hotkeys are now local, so no `null` is needed.) Set every `hotkeys` entry
  to `null`. Carbon registration was system-wide, so a second instance with the default
  `cmd+shift+\` failed and showed the "Global Shortcut Unavailable" alert.
- `SMAppService.mainApp` ("Open at Login") launches the bundle without arguments, so it only
  starts `default`. Start other instances with a LaunchAgent that passes `--config`.
- Both instances share one bundle ID, so they share the WebKit cookie and website-data store.
- `open -a Gander` with any instance running only activates that process; it does not start
  `default`. Use `open -n`. The same LaunchServices rule can stop the "Open at Login" item when a
  LaunchAgent instance starts first, so on this machine both instances run from LaunchAgents
  (`~/Library/LaunchAgents/io.gander.default.plist`, `io.gander.llm.plist`) and "Open at Login"
  stays off. With both on, two `default` processes start and the second one shows the hotkey alert.

### Two `frameConfig` overload helpers in AppDelegate

`AppDelegate` has two private helpers with identical signatures returning a `FrameConfig`:
one reads from a `[AnyHashable: Any]?` userInfo dictionary (used by IPC notifications) and one
reads from `URLComponents?` query items (used by the `gander://` URL scheme). The duplication
avoids a shared extraction layer that would need to bridge the two formats — both callers are
one line each.

### WKWebView privacy vs. Safari — what's missing and what's possible

WKWebView shares Safari's rendering engine and gets ITP (Intelligent Tracking Prevention),
HTTPS upgrades, same-site cookie isolation, and WebKit fingerprinting mitigations. But several
Safari privacy features are Safari-specific and not available to WKWebView at all:

| Feature | WKWebView | Can be added? |
|---|---|---|
| Intelligent Tracking Prevention | ✅ same engine | — |
| HTTPS upgrade | ✅ | — |
| Fingerprinting mitigations | ✅ | — |
| Private Browsing (ephemeral session) | manual only | ✅ `websiteDataStore = .nonPersistent()` |
| Fraudulent website warnings (Safe Browsing) | ❌ | ⚠️ only via custom `WKNavigationDelegate` + your own list |
| iCloud Private Relay (IP hiding) | ❌ Safari-only | ❌ not exposed to apps |
| Link Tracking Protection (strip `?fbclid=` etc.) | ❌ Safari-only | ⚠️ partial — strip known params in `decidePolicyFor navigationAction` |
| Safari Extensions / content blockers (user-installed) | ❌ | ✅ first-party `WKContentRuleList` only |

**What can realistically be added to Gander:**
- **Ephemeral sessions**: already easy — pass `.nonPersistent()` to `WKWebViewConfiguration.websiteDataStore`. Could be a per-site config option.
- **Link Tracking Protection**: intercept navigation in `WKNavigationDelegate.decidePolicyFor` and strip well-known tracking params (`fbclid`, `gclid`, `utm_*`, etc.) before loading. Straightforward but requires maintaining the param list.
- **Content blocking**: compile a `WKContentRuleList` from a JSON rule list (e.g. EasyList format) and attach it to the `WKWebViewConfiguration`. This is how third-party iOS browsers get ad blocking.

**What cannot be added:**
- iCloud Private Relay is a system-level feature gated to Safari by Apple. No API exposes it to third-party apps.
- Safe Browsing (Google's list) is also not exposed — you'd need to query the Google Safe Browsing API yourself with a key and check every navigation.

---

## Workflow

### Local development

```bash
bash publish.sh           # swift build + logic tests + build.sh + smoke tests + /Applications install
bash publish.sh --open    # same + opens Gander.app
bash publish.sh --skip-smoke   # skip smoke tests (faster iteration)
```

Under the hood `publish.sh` runs:
1. `swift build` — fast compiler check
2. `bash logic-test.sh` — source-level unit tests (Config.swift only, no app launch)
3. `bash build.sh` — full release bundle → `./Gander.app` (repo root, not /Applications)
4. `bash smoke-test.sh` — launches an isolated instance, exercises CLI commands

### Release

```bash
bash scripts/release.sh 0.2.0
```

1. Guards: no dirty working tree, tag doesn't already exist
2. Runs logic tests
3. Pushes `main` (so the tag lands on the remote HEAD)
4. Creates and pushes tag `v0.2.0`
5. GitHub Actions builds the zip, creates the GitHub Release, updates `Casks/gander.rb` inline

**After tagging:** always check `gh run list --repo o-o-o-o-o/gander --limit 3` before
reporting done. The v0.1.5 CI run failed (Cask push rejected because `main` wasn't pushed
before the tag) and required manual recovery. That's why `release.sh` now pushes main first.

### Versioning

Semver pre-1.0: `0.x.y`. Minor bump for new user-visible features, patch for fixes.

---

## Gotchas Discovered

### logic-test.sh must use relative source paths

`swiftc Sources/Gander/Config.swift` — not an absolute path. Absolute paths work on the local
machine and break in CI because CI clones to a different directory. Learned from the
"Fix CI: remove hardcoded local path in logic-test.sh" commit.

### App bundle binary naming — APFS case-insensitive collision (caused a silent launch failure)

Originally both binaries were placed in `Gander.app/Contents/MacOS/`:
- `Gander` — the app executable
- `gander` — the CLI tool

APFS (the default macOS filesystem) is **case-insensitive**: `gander == Gander` in the same
directory. When Homebrew or macOS extracted the release zip, the CLI binary silently
**overwrote** the app binary. The app would appear to launch, actually run the CLI binary,
print a usage error to stderr, and exit immediately — with no visible error to the user.

Fix: rename the CLI copy inside the bundle to `gander-cli`:
```bash
cp "$CLI_BIN" "$APP/MacOS/gander-cli"   # was: gander
```

The Homebrew Cask then symlinks it back under the correct name in the user's PATH:
```ruby
binary "#{appdir}/Gander.app/Contents/MacOS/gander-cli", target: "gander"
```

So the rename chain is: SPM produces `gander` → bundled as `gander-cli` → Cask exposes as `gander`.

**If you add another binary to the bundle in the future**, check for case-insensitive collisions
with `Gander` (the app executable) before naming it.

### Cask directory must be `Casks/` (plural)

Homebrew's tap lookup convention requires `Casks/` (plural). `Cask/` (singular) is not found.
Learned from "Rename Cask/ to Casks/".

### Use explicit `--product` flags with `swift build`

With two executable targets in `Package.swift`, `swift build -c release` alone can pick the
wrong default. Always use `--product GanderApp` and `--product gander` explicitly.
Learned from "Improve release build: explicit --product flags, nm sanity check".

### `GITHUB_TOKEN` cannot trigger other workflow files

Creating a GitHub Release with `GITHUB_TOKEN` does not fire `release: published` events in
sibling workflow files. This is why the Cask update runs as a final step of the release
workflow rather than a separate workflow. `update-cask.yml` exists only as a manual
`workflow_dispatch` fallback when something goes wrong.

### Node.js 24 for GitHub Actions (required from June 2, 2026)

GitHub Actions deprecated Node.js 20 runners. Add this to any workflow that uses JS-based
Actions (like `actions/checkout`):
```yaml
env:
  FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true
```

### Use `ditto` for zipping macOS app bundles

```bash
ditto -c -k --keepParent Gander.app Gander-v0.2.0.zip
```

`zip -r` can corrupt resource forks and the `.app` structure. `ditto` is the correct tool.

### `softprops/action-gh-release@v2` auto-generates release notes

`generate_release_notes: true` produces release notes from commit messages since the last tag.
No configuration needed.

### `--shortcut` was documented in the Help panel but not implemented in the CLI

The Help panel HTML (`HelpContent.swift`) documented:
```
gander <name> open <url> --shortcut <1–9>
```
But `parseURLAndFrame` in `gander-cli/main.swift` only handled `--x`, `--y`, `--width`,
`--height` — passing `--shortcut` would hit the `hasPrefix("--")` branch and exit with
"unknown option". The URL scheme (`gander://open?url=...&shortcut=1`) worked correctly.

Fix: extract `--shortcut` before calling `parseURLAndFrame` in the `open` case, validate
it's 1–9, then include it in the IPC `userInfo` dict as `"shortcut"`.

Pattern to avoid: when adding a feature via two paths (URL scheme + CLI), verify both paths
are wired up. The help panel now serves as the authoritative list of what's supported.

### Named frames, relative sizing, and display auto-switch (laptop / studio)

**Problem:** Fixed `width` / `height` / `x` / `y` in `~/.config/gander/default.json` are absolute
points from one monitor. Moving between a laptop and a docked studio leaves the sidebar the wrong
size or off-screen. `gander frame --height 0` clamps to 240pt (minimum), not “full screen”; omitting
`--height` leaves the current height unchanged — there was no CLI way to mean “100% of visible height.”

**Design:**

- `frames` — named presets (`laptop`, `studio`) with dimensions as numbers (`420`) or strings
  (`"30%"`, `"100%"`, `"full"`) and position as `"right"` / `"bottom"` or points.
- `frameAuto.match` — rules on `screenCount` / `screenCountMin`; first match wins.
- `NSApplication.didChangeScreenParametersNotification` — debounced ~100ms; on screen count change
  (or `onLayoutChange: true`), re-apply the matched preset on **`NSScreen.main`** (menu bar display).
- Single resolver: `FrameResolver.computedRect` — avoid naming a method `resolve` on `NSRect`/`CGRect`
  context; Swift picked the wrong overload (`NSRect(dictionaryRepresentation:)`).

**Launch:** `launchPresetName(screenCount:)` uses `frameAuto` first, then `"frame"`, then `"default"`.
Geometry is resolved on `NSScreen.main`. Do **not** open `sites[0]` when `sites` is non-empty —
use `defaultUrl` for startup and **⌘0** to return to it (`pinned` ⌘1–⌘9 stays on list sites).

**CLI:** `gander frame studio` posts `preset` in IPC `userInfo`. Rebuild **both** `Gander.app` and the
`gander` binary — Homebrew’s `/opt/homebrew/bin/gander` stays old until `brew upgrade --cask gander`;
old CLI shows usage without `<preset>` and rejects `studio` as an unexpected argument.

**Local build:** `swift build` alone updates `.build/release/` only; `bash build.sh` copies into
`./Gander.app`. Use `bash publish.sh` before smoke-testing a release candidate.

### `defaultUrl` vs first site in `sites`

Startup used `if let first = config.sites.first { switchToSite(first) }` whenever the sites array
was non-empty, so `defaultUrl` in JSON was ignored for anyone with a site list (common). Fix: always
`openURL(config.defaultUrl)` on launch. ⌘0 uses the same URL when the panel is key (like ⌘1–⌘9).

### `nm` binary sanity check in build-release.sh

The release build checks `nm "$APP_BIN" | grep AppDelegate` to confirm the right binary was
built. Without this check, a wrong-product build can silently produce a `gander`-CLI-shaped
binary named `GanderApp` — which launches and exits immediately with no error.

---

## Config Schema Reference

*Since the rename the file lives at `~/.config/ur/browse/<pot>/config.json`. `color` is now `glaze` (old key still read); new keys: `glaze`, `ephemeral` (in-memory website data), and an optional `id` on each site. The example below is otherwise current.*

```json
{
  "name":            "default",
  "glaze":           "#4A90D9",
  "ephemeral":       false,
  "width":           420,
  "defaultUrl":      "https://google.com",
  "chrome":          true,
  "stripeHeight":    3,
  "externalBrowser": "Safari",
  "pinned":          "auto",
  "frame":           "studio",
  "frames": {
    "laptop": {
      "width": "30%",
      "height": "100%",
      "x": "right",
      "y": "bottom"
    },
    "studio": {
      "width": 420,
      "height": "100%",
      "x": "right",
      "y": "bottom"
    }
  },
  "frameAuto": {
    "match": [
      { "screenCount": 1, "frame": "laptop" },
      { "screenCountMin": 2, "frame": "studio" }
    ]
  },
  "hotkeys": {
    "toggle": "cmd+shift+\\",
    "sites":  "cmd+shift+/",
    "next":   "cmd+shift+]",
    "prev":   "cmd+shift+["
  },
  "sites": [
    { "id": "gh", "name": "GitHub",  "url": "https://github.com" },
    { "name": "Pinned",  "url": "https://example.com", "shortcut": 1 }
  ]
}
```

All fields optional; defaults are sane. Legacy top-level `width` / `height` / `x` / `y` still work
as the implicit `"default"` preset when `frames` is omitted.

- **`defaultUrl`** — loaded on app launch and with **⌘0** (panel must be key window).
- **`sitesCommand`** — shell command; stdout JSON `[{name,url,...}]` replaces `sites`. Run at
  launch and on each picker open. Failure, timeout or empty output keeps the current list.
- **`pinned`** — `"auto"` (⌘1–⌘9 for first 9 sites), `"manual"` (per-site `shortcut`), or omit.
- **`frames` / `frame` / `frameAuto`** — named layouts; auto-switch on display plug/unplug via
  `frameAuto.match` and `NSScreen.screens.count`; geometry resolved on main screen.

Hotkey format: `"modifier+modifier+key"` where modifiers are `cmd`, `shift`, `option`/`alt`,
`ctrl`. Set to `null` or `""` to disable.

---

## Reuse as a Template

The reusable skeleton is **`Sources/UrKit` + `UrAppSpec`** (in `UrKit/CLI.swift`) — "clay".
UrKit gives a new Ur app pots (paths, names, storage ids), the addressed `Request`/`Response`
shape (argv, `<scheme>://` URLs and the wire are one parser), the Unix-socket IPC, and the whole
CLI (`pots`, `throw`, `start`, `--json`, `--alfred`, autostart, LaunchAgent via `--login`). An app
supplies only a spec and its own behaviour.

To make a new Ur app (ur-mail, ur-notes, …):
- Depend on the `UrKit` product; copy `Sources/UrBrowseSpec` → `Sources/Ur<App>Spec` and fill in
  `UrAppSpec` (app name, command, bundle id, schemes, verbs, autostart verbs, `throw` options,
  usage text). The spec is a separate module so the app and the CLI share one verb list.
- `Sources/ur-<app>-cli/main.swift` is one line: `UrCLI(<App>Spec.spec).run()`.
- In the app: start an `IPCServer` on `pot.socketURL` (exit if the pot is already running), turn
  each `Request` into a typed command in one validator (see `BrowseCommand`), and dispatch in one
  place (`AppDelegate.handle` / `execute`). Forward URL-scheme events for other pots to their
  socket.
- Keep pure logic in files that wrap `import UrKit` in `#if canImport(UrKit)` so `logic-test.sh`
  can compile them as one module.
- Reuse `scripts/bundle.sh`, the Cask layout (`ur-<app>` plus a binary stanza pointing at
  `Contents/MacOS/ur-<app>-cli`), `publish.sh` and the GitHub Actions release flow.

What carries over unchanged from the original template: no Xcode project or Developer account,
Homebrew Cask distribution with automated SHA256 and version updates, CI/CD (build → artifact →
Release → Cask update in one workflow). Hotkeys are local to each pot's panel (see the superseded Carbon section).

---

## AppKit Fundamentals (First-Time Notes)

Patterns that are non-obvious when coming from web, scripting, or other UI frameworks.
Experienced AppKit developers treat these as background knowledge — worth capturing explicitly
since this is a first native Mac app.

### Why AppKit and not SwiftUI

SwiftUI is Apple's modern framework, but it couldn't do what Gander needs:

- No `NSPanel` equivalent — SwiftUI's window API doesn't expose the `.nonactivatingPanel`
  style mask, `collectionBehavior`, or `hidesOnDeactivate`
- No way to make a window float across all Spaces and window managers at a specific level
- Carbon hotkeys are a C API — they work fine alongside AppKit with no bridging needed

SwiftUI is excellent for standard app windows, preference panels, and typical Mac app UIs.
For anything that requires precise control over window behavior (floating panels, non-activating
windows, system-wide hotkeys), AppKit gives you direct access to the underlying Cocoa layer.
You can also mix them: a SwiftUI view inside an `NSHostingView` inside an `NSPanel` is valid.

### macOS App Lifecycle

`main.swift` is the true entry point. The pattern:
```swift
let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon, no app switcher
let delegate = AppDelegate(config: config)
app.delegate = delegate
app.run()                             // blocks forever — this is the run loop
```

`app.run()` starts the **run loop**, which drives everything: UI events, timers, notifications,
delegate callbacks. All of this happens on the main thread. Never block the main thread — no
`Thread.sleep`, no synchronous file I/O, no synchronous network calls. If the main thread
blocks, the whole app freezes.

**`setActivationPolicy(.accessory)`** — the app won't appear in the Dock or Cmd-Tab switcher.
`.regular` (the default) shows in both. `.prohibited` completely hides the app.

**`LSUIElement = true` in Info.plist** is a second layer: it suppresses the app from appearing
in contexts that `.accessory` alone might miss. Both are needed for a pure menu bar app.

### `translatesAutoresizingMaskIntoConstraints = false` — Required for Every Programmatic View

This is one of the most common AppKit/UIKit pitfalls. When you create an `NSView` in code
and add it to a layout, you **must** set this before activating constraints:

```swift
let myView = NSView()
myView.translatesAutoresizingMaskIntoConstraints = false   // ← always, immediately
parentView.addSubview(myView)
NSLayoutConstraint.activate([
    myView.topAnchor.constraint(equalTo: parentView.topAnchor),
    ...
])
```

**Why:** By default, AppKit auto-generates constraints from the view's `autoresizingMask`
(a legacy layout system). Those auto-generated constraints conflict with yours, causing
broken layouts and console warnings. Setting this to `false` disables the auto-generation.

If you see layout ambiguity warnings or views appearing at the wrong position, this is the
first thing to check.

### `@objc` and Selectors

AppKit predates Swift by decades and is written in Objective-C. Methods used as action targets
(`NSButton.action`, `NSMenuItem.action`, Carbon callbacks) must be exposed to the Obj-C runtime
via `@objc`:

```swift
@objc private func togglePanel() { panel?.toggle() }

// Used as:
button.action = #selector(togglePanel)
button.target = self
```

Without `@objc` you get a compile error: *"argument of '#selector' refers to instance method
that is not exposed to Objective-C."*

Delegate protocol methods (e.g. `NSMenuDelegate`, `NSTableViewDelegate`) are implicitly
`@objc` because the protocols themselves are Objective-C. You only need to add `@objc`
explicitly to your own methods that you pass as selectors.

### `[weak self]` in Closures — Avoiding Retain Cycles

Swift uses ARC (Automatic Reference Counting) for memory management. A closure captures
everything it references, keeping those objects alive. If an object holds a closure that also
holds a strong reference back to that object, neither is ever released — a **retain cycle**.

```swift
// Retain cycle: SidebarPanel → pickerView.onSelect → (captures self = SidebarPanel)
pickerView.onSelect = { url in self.pickerDidSelect(url: url) }

// Correct: weak reference breaks the cycle
pickerView.onSelect = { [weak self] url in self?.pickerDidSelect(url: url) }
```

`[weak self]` makes `self` a weak optional inside the closure. If `self` is deallocated before
the closure fires, `self?` is nil and the call is safely skipped.

**Rule of thumb:** any closure stored as a property on another object that captures `self`
→ use `[weak self]`. Closures passed as inline arguments that aren't stored (e.g. `UIView.animate`)
→ usually fine without it.

### `isReleasedWhenClosed = false`

By default, `NSWindow` (and `NSPanel`) deallocates itself when closed. For Gander's panel,
which is hidden and re-shown rather than truly closed, this would destroy the panel and all
its WebView sessions.

```swift
isReleasedWhenClosed = false
```

Required for any window you intend to show more than once. Without it, the second `show()`
call crashes or silently does nothing against a dead object.

### Passing `self` to C Callbacks (the Unmanaged Pattern)

Carbon APIs use C conventions: callbacks receive a `void*` user-data pointer. Bridging a
Swift object through a C pointer requires `Unmanaged`:

```swift
// Wrap self as an opaque pointer — "passUnretained" means ARC doesn't transfer ownership.
// We guarantee self stays alive for the callback's lifetime (it's the AppDelegate).
let selfPtr = Unmanaged.passUnretained(self).toOpaque()

InstallEventHandler(..., selfPtr, &carbonHandler)

// Inside the C callback — recover the Swift object without claiming ownership
let me = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()
DispatchQueue.main.async { me.panel?.toggle() }
```

`passRetained` / `takeRetainedValue` would transfer ARC ownership (incrementing the retain
count), requiring a matching `release()`. `passUnretained` / `takeUnretainedValue` bypasses ARC
entirely — safe here because AppDelegate lives for the entire app lifetime.

### UI Updates Must Happen on the Main Thread

Carbon's event callback fires on whatever thread the OS uses. AppKit requires all UI mutations
to happen on the main thread — calling UI code off the main thread causes crashes or silent
corruption that's hard to reproduce.

```swift
// Always dispatch UI work from background/callback contexts
DispatchQueue.main.async {
    self.panel?.toggle()
}
```

If you see intermittent crashes or glitchy UI in response to hotkeys or notifications, check
whether the triggering callback is on the main thread.

### KVO — Watching Properties for Changes

Key-Value Observing lets you watch any `@objc dynamic` property for changes. Gander uses it
to mirror the WKWebView's page title into the panel's title bar:

```swift
// .initial fires immediately with the current value
// .new fires on every subsequent change
titleObservation = wv.observe(\.title, options: [.initial, .new]) { webView, _ in
    self.title = webView.title ?? "Sidebar"
}
```

The observation token (`NSKeyValueObservation`) **must be kept alive** — the moment it's
deallocated (or set to `nil`), observation stops. Store it in a `var` property. Reassigning
the property automatically cancels the previous observation.

### `NSVisualEffectView` for Frosted Glass

The site picker's backdrop is `NSVisualEffectView`, which uses the system compositor to blur
and tint content:

```swift
let fx = NSVisualEffectView()
fx.material = .sidebar          // style — .sidebar, .menu, .popover, .hudWindow, etc.
fx.blendingMode = .behindWindow // blur what's behind the window (not just behind the view)
fx.state = .active              // always active, not just when the window is key
```

`.behindWindow` is correct for a floating panel that appears over other apps' windows. 
`.withinWindow` only blurs content within the same window, which looks wrong here.

### The Responder Chain

AppKit routes keyboard events through a chain: first responder → window → application →
app delegate. Each object in the chain can handle or forward the event.

`makeFirstResponder(_:)` designates who gets keyboard input:

```swift
makeFirstResponder(pickerView.searchField)  // direct keyboard to search field
makeFirstResponder(activeWebView)           // return it to the web view
```

With `.nonactivatingPanel`, the panel doesn't steal focus when shown — it won't become key
automatically. This is why `showSitePicker()` calls `makeKeyAndOrderFront` before
`makeFirstResponder`, and why `becomeKey()` is overridden to refocus the search field if the
picker is open when the panel eventually does become key.

### How the `gander://` URL Scheme Works (now `ur-browse://` and `gander://`)

*Both schemes are registered by the bundle; see "URL scheme events go to an arbitrary process of the bundle" for the multi-pot twist.*

URL scheme registration happens via Launch Services when the app is installed. The system
routes `gander://` URLs to your app via Apple Events:

```swift
NSAppleEventManager.shared().setEventHandler(
    self, andSelector: #selector(handleURL(_:withReplyEvent:)),
    forEventClass: AEEventClass(kInternetEventClass),
    andEventID: AEEventID(kAEGetURL)
)
```

`kInternetEventClass` + `kAEGetURL` is the specific Apple Event the OS sends when a URL with
your registered scheme is opened anywhere in the system. This is why `make install` runs
`lsregister` — it tells Launch Services that this `.app` handles `gander://`. Without that
registration step, `open -g "gander://toggle"` just fails silently.

### `SMAppService` — Login Items (Open at Login)

macOS 13+ uses `SMAppService` to register an app to launch at login:

```swift
import ServiceManagement

let service = SMAppService.mainApp
try service.register()    // add to login items
try service.unregister()  // remove from login items
service.status            // .enabled / .notRegistered / .requiresApproval / .notFound
```

This replaces the old `SMLoginItemSetEnabled` API. The `status` property lets you show a
checkmark in the menu — check it in `menuWillOpen` (not at menu creation time) so it reflects
the current state rather than the state at launch.

### Swift's `Codable` — Graceful Config Loading

`AppConfig` uses a custom `init(from decoder:)` rather than the auto-synthesized one because
every field needs a default:

```swift
// Auto-synthesis would throw if any field is missing.
// Custom init reads each field with a fallback:
name = (try? c.decode(String.self, forKey: .name)) ?? "default"
```

`try? c.decode(...)` returns `nil` if the key is missing or the value is the wrong type —
never throws. The `?? "default"` then provides the fallback. This means a completely empty
JSON object `{}` is a valid config (uses all defaults), and a partial config only overrides
what's present.

### The `.app` Bundle Structure

macOS doesn't distribute raw executables — it uses `.app` bundles, which are directories
that the Finder presents as a single file:

```
Gander.app/
  Contents/
    MacOS/
      Gander        ← main executable (CFBundleExecutable)
      gander-cli    ← bundled CLI tool
    Resources/
      AppIcon.icns  ← app icon
      greg.png      ← menu bar icon
    Info.plist      ← metadata: bundle ID, version, URL schemes, LSUIElement, etc.
```

`Info.plist` is how macOS knows everything about your app without running it: what executable
to launch, what URL schemes it handles, whether to show in the Dock, what its icon is, etc.
`swift build` produces binaries; `build.sh` manually assembles the `.app` directory structure
and writes `Info.plist` — this is what Xcode normally does for you.

### macOS Security: Gatekeeper, Quarantine, and Notarization

When you download an `.app` from the internet, macOS applies a quarantine extended attribute
(`com.apple.quarantine`) to the file. On first launch, Gatekeeper checks:
1. Is the app signed with a Developer ID certificate? (requires paid Apple Developer account)
2. Is it notarized? (submitted to Apple's servers for malware scan)

If neither, Gatekeeper blocks launch and shows "cannot be opened because it is from an unidentified developer." The user can override via System Settings → Privacy & Security.

Since Gander is unsigned and unnotarized, Homebrew's Cask caveats instruct users to remove the quarantine attribute manually after install, or approve the app via System Settings:

```bash
xattr -dr com.apple.quarantine /Applications/Gander.app
# or: System Settings → Privacy & Security → Open Anyway
```

Note: `brew install --no-quarantine` was removed from Homebrew — the flag no longer exists.
The `xattr` approach is the only post-install workaround now.

---

### JSONSerialization.data(withJSONObject:) silently fails on bare strings

When building the find-bar match counter, we used `JSONSerialization.data(withJSONObject: text)` to produce a safe JSON string literal to inject into JavaScript. This silently returns `nil` (or throws, swallowed by `try?`) because `JSONSerialization` only accepts a top-level Array or Dictionary — a bare String is not valid JSON at the top level per the spec.

Root cause: the method's name implies "convert this object to JSON data," but the constraint is that the top-level value must be an array or dict. The failure mode is silent when using `try?`.

Fix: manually escape the string for embedding in a JS string literal:

```swift
let escaped = text
    .replacingOccurrences(of: "\\", with: "\\\\")
    .replacingOccurrences(of: "\"", with: "\\\"")
    .replacingOccurrences(of: "\n", with: "\\n")
    .replacingOccurrences(of: "\r", with: "\\r")
let js = "const t = \"\(escaped)\";"
```

Alternatively, use `JSONEncoder().encode(text)` which does handle bare strings, or wrap in an array and strip the brackets.

---

### WKWebView find-in-page on macOS: what works and what doesn't

Several APIs look like they should work for in-page search but don't on macOS native (AppKit):

**`findInteractionEnabled` / `WKFindInteraction` / `UIFindInteraction` — iOS only.**
Despite appearing in WKWebView documentation, these are UIKit APIs (note the `UI` prefix).
They are available on iOS 16+, iPadOS 16+, and Mac Catalyst — but NOT native macOS. The
Swift compiler will error: `value of type 'WKWebView' has no member 'findInteraction'`.

**`performTextFinderAction(_:)` / `NSTextFinderClient` — silently does nothing on WKWebView.**
NSView inherits `performTextFinderAction`, and WKWebView is advertised as supporting
`NSTextFinderClient`. In practice, calling `performTextFinderAction` with
`NSTextFinder.Action.showFindInterface` on a WKWebView does not show any UI. The call
succeeds but nothing happens.

**The correct macOS approach: `WKWebView.find(_:configuration:completionHandler:)`**
This is the public API that actually works. It finds and highlights text in the page,
scrolls to the match, and calls the completion with `WKFindResult`. Use `WKFindConfiguration`
to set `backwards`, `wraps`, and `caseSensitive`.

Key limitations of this API:
- `WKFindResult` only has `matchFound: Bool` — no match count, no current index.
- There is no `clearMatches()` or equivalent public API.
- Match count requires a separate JS call (`document.body.innerText.match(re)?.length`).
- "X of Y" position tracking is not directly supported; you'd have to count navigations
  manually, which can drift if the page content changes.

**Highlight color: inject `::selection` CSS.**
`WKWebView.find()` creates a native text selection on the found text. The `::selection`
CSS pseudo-element applies to that selection, so injecting a style tag with
`*::selection { background: rgba(255,140,0,.75) !important; }` gives a more prominent,
custom highlight color. Inject on find-bar open, remove on close.

**Custom find bar: overlay at bottom of webContainer.**
Since there is no built-in find UI on macOS, implement a custom `NSView` overlay pinned
to the bottom of the webContainer. Use `NSSearchField` with `NSSearchFieldDelegate` for
live search (`controlTextDidChange`), plus prev/next buttons and a status label.
`NSVisualEffectView` with `.hudWindow` material gives a native frosted-glass background.

---

### `WKWebView.url` can be `about:blank` even when a real page is loaded

`WKWebView.url` sometimes returns `about:blank` (or nil) on a page that visually appears fully
loaded — observed particularly on pages that redirect or that use history.pushState. Do not rely
on `wv.url` alone when you need the current page URL (e.g. for "Open in browser").

Fix: fall back to `evaluateJavaScript("location.href")` if `wv.url` is nil or `about:blank`:

```swift
func resolvePageURL(from wv: WKWebView, completion: @escaping (URL?) -> Void) {
    if let url = wv.url, url.absoluteString != "about:blank" { completion(url); return }
    wv.evaluateJavaScript("location.href") { result, _ in
        DispatchQueue.main.async { completion((result as? String).flatMap(URL.init(string:))) }
    }
}
```

---

### Injecting text into WKWebView active elements via JavaScript

When normal AppKit paste fails (e.g. concealed pasteboard), you can inject text directly into
the focused DOM element via `evaluateJavaScript`. Use `JSONEncoder` to safely encode the string:

```swift
guard let encoded = try? JSONEncoder().encode(text),
      let json = String(data: encoded, encoding: .utf8) else { return }
let script = """
(function(t) {
    var el = document.activeElement;
    if (!el) return false;
    if (el.isContentEditable) {
        document.execCommand('insertText', false, t); return true;
    }
    if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') {
        var s = el.selectionStart ?? el.value.length;
        var e = el.selectionEnd ?? s;
        el.value = el.value.slice(0, s) + t + el.value.slice(e);
        el.selectionStart = el.selectionEnd = s + t.length;
        el.dispatchEvent(new Event('input', {bubbles: true}));
        el.dispatchEvent(new Event('change', {bubbles: true}));
        return true;
    }
    return false;
})(\(json))
"""
wv.evaluateJavaScript(script) { _, _ in }
```

`document.execCommand('insertText', false, t)` is the only reliable way to insert into
contentEditable elements — direct DOM manipulation doesn't fire framework change events
(React, Vue, etc. won't see the change). For INPUT/TEXTAREA, dispatch both `input` and
`change` events so frameworks pick up the new value.

---

### `build.sh` (local build) silently produced an app with no CLI → external triggers broke

Symptom: the global trigger `fn + -` (a BetterTouchTool shortcut that runs `gander toggle`)
stopped working. It looked like a hotkey problem, but `fn` isn't even a Carbon modifier — the
trigger is external, so it can never have been one of Gander's `RegisterEventHotKey` hotkeys.

Root cause: `build.sh` only copied `GanderApp → Contents/MacOS/Gander`; it never built or
bundled `gander-cli`. Only `scripts/build-release.sh` (the CI build) bundles `gander-cli`.
The Homebrew Cask symlinks `gander → Contents/MacOS/gander-cli`, so when a local `build.sh`
build got copied over `/Applications/Gander.app`, that symlink became dangling. `which gander`
returned "not found" and every external trigger (CLI, BTT, `gander://` URL scheme) silently
failed — the app itself looked completely fine.

How we spotted it: installed app reported version `0.1.14-1-g<sha>-dirty` (a `git describe`
dev build), but Homebrew's Caskroom only knew a clean release. The "we use brew" install had
been overwritten by an incomplete local build.

Fix:
- `build.sh` now also `cp .build/release/gander "$APP/MacOS/gander-cli"` so local test builds
  are complete. (`swift build -c release` already builds all products, so the binary exists.)
- For the user's daily app, `brew reinstall --cask gander` restores a complete bundle and the
  `gander` symlink. Never copy a `build.sh` output over the brew install.

### Carbon hotkey registration can fail silently (defensive, secondary)

`RegisterEventHotKey` returns a non-zero `OSStatus` when a shortcut is already taken (e.g. two
Gander copies running, or another app owns it). If ignored, startup looks normal but the
hotkey never fires. `registerHotkey` now checks the status and surfaces a warning (stderr +
alert for the toggle hotkey). Note: this was *not* the cause of the `fn + -` regression above —
that was the missing CLI binary — but it's a worthwhile guard.

### `charactersIgnoringModifiers` still applies Shift — bracket/symbol shortcuts broke

The local key monitor handled `⌘⇧[` / `⌘⇧]` (site cycling) by checking
`charactersIgnoringModifiers == "[" / "]"`. That never matched: `charactersIgnoringModifiers`
ignores Command/Option/Control but **keeps Shift**, so `⌘⇧[` arrives as `"{"` and `⌘⇧]` as
`"}"` (same reason `⌘⇧O` arrives as `"O"`, already noted in the code). The bracket shortcuts
only ever appeared to work via the *global* Carbon `next`/`prev` hotkeys (keyCode-based, so
Shift doesn't change them). Once those globals were disabled in config, tab cycling was dead.

Fix: match the shifted glyphs `"{"` / `"}"`, with bracket keyCodes (33 = `[`, 30 = `]`) as a
layout-robust fallback. The same bug existed for two sibling shortcuts that also hold Shift —
`⌘⇧G` (find previous) and `⌘⇧Z` (redo) compared against `"g"` / `"z"` but Shift delivers
`"G"` / `"Z"`; fixed by comparing `ch?.lowercased()` (as `⌘⇧O` already did). Audit rule: any
Shift-bearing shortcut matched via `charactersIgnoringModifiers` must compare case-insensitively
or by keyCode.

**Superseded (2026-09-30):** switched the key monitor from `charactersIgnoringModifiers` to
`event.characters(byApplyingModifiers: [])`, found while surveying a comparable WKWebView
browser's shortcut handling (driceroland/Search, `Shortcuts.swift`). Passing an explicit empty
modifier set recovers the base key regardless of Shift, so `⌘⇧[` now arrives as `"["` directly
— no shifted-glyph matching, no `.lowercased()`. The bracket keyCode fallback stays; it's for
layout differences, not Shift. The `.lowercased()` workarounds for `⌘⇧O`/`⌘⇧G`/`⌘⇧Z` are gone.

### Top stripe repurposed as a page-load progress bar (2026-09-30)

The top color stripe (`config.color` / `config.stripeHeight`, previously a static full-width
bar) now animates its width with `WKWebView.estimatedProgress` — 0→100% while loading, snaps
to full on finish, collapses back to 0 after a short delay. `estimatedProgress`/`isLoading` are
native KVO properties on `WKWebView`; no custom progress tracking needed. Observation is bound
per active session in `activateWebView`, the same place `titleObservation` already gets rebound
on site switch — same pattern, so switching sites re-syncs the bar instantly (no animation) to
whatever state the newly-active session is already in.

Regression: the bar previously served double duty as a permanent per-instance color identifier
(see README "Multiple instances") — with multiple Gander instances running, each one's stripe
was always visible so you could tell them apart at a glance. That's gone now: the bar is only
visible during an active load. If that identification need comes back, it'll need a separate
always-on element instead of reusing this one.

Default `stripeHeight` dropped from 3 to 2 — a persistent full-width identity stripe reads
differently than a thin transient progress indicator; 2pt is closer to Safari/Chrome's own bar
weight. Both `color` and `stripeHeight` were already config fields, so no new config surface
was needed for this.

Verifying this kind of change is awkward in this environment: `screencapture` fails
(`could not create image from display`) even with the shell sandbox disabled — no macOS Screen
Recording permission granted to the process running shell commands here. Verified instead by
launching an isolated instance (own config, own window position) and asking the user to look at
it directly while triggering loads — a fast page (e.g. Wikipedia) collapses the bar too quickly
to reliably catch, so use an artificially slow one (`https://httpbin.org/delay/4`) to get a
multi-second window to confirm against.

### Scrollbar hidden via injected CSS user script

Added a `WKUserScript` (CSS `::-webkit-scrollbar{display:none}` + `scrollbar-width:none`,
injected at `.atDocumentStart`, `forMainFrameOnly: false`) through a custom
`WKWebViewConfiguration` in `makeWebView()`. Scrolling itself is unaffected — trackpad/keyboard
scrolling doesn't go through the visible track. `forMainFrameOnly: false` so embedded
iframes (maps, embeds) get it too, not just the top-level page.

Checked driceroland/Search for an existing implementation first (GitHub code search across the
repo for `scrollbar`, `NSScroller`, `webkit-scrollbar`, `scrollbar-width` — zero hits anywhere).
They don't hide scrollbars; there was nothing to port. Did confirm their general CSS-injection
idiom (a `Veiling.style(css)` helper wrapping a `WKUserScript` at `.atDocumentStart`, per-frame)
matches the standard approach used here.

### Design requirement: site-cycling (`⌘⇧[` / `⌘⇧]`) must be local to Gander-frontmost

Tab cycling must only fire when Gander is the active app — never system-wide. Two mechanisms
existed: the global Carbon `next`/`prev` hotkeys (system-wide) and the panel's local key
monitor (only fires while Gander is active). The local monitor is the correct home for this;
the global hotkeys are opt-in and left `null` in config. A `NSEvent` local monitor only sees
events destined for our app, so it's inherently scoped to "frontmost" without an explicit
`isKeyWindow` guard.

### "Gander is damaged and can't be opened" = broken ad-hoc signature (2026-10-08)

Takeaway: `build-release.sh` must `codesign --force --deep --sign -` the assembled bundle.
SwiftPM's linker ad-hoc-signs only the bare Mach-O. We then add `Info.plist` and `Resources/`
by hand, so the seal is invalid (`code has no resources but signature indicates they must be
present`). Unquarantined, it still runs. With the Homebrew quarantine flag, Apple Silicon
Gatekeeper calls it "damaged" — not the usual "unidentified developer" prompt, so
`xattr -dr com.apple.quarantine` and Open Anyway can both fail to help. Fix: re-sign at build
time (added to `scripts/build-release.sh` and `build.sh`); ships in the next release.
Immediate fix on an installed copy: `codesign --force --deep --sign - /Applications/Gander.app`.
**Superseded (2026-10-14):** the re-sign was necessary but not sufficient — see next entry.

### "Damaged" persists with a valid ad-hoc signature: strip quarantine in the Cask (2026-10-14)

Takeaway: an ad-hoc signed, un-notarized app that has the quarantine flag is reported as "damaged"
on Apple Silicon. A valid signature does not prevent this. v0.3.1 passed `codesign --verify
--deep --strict`. But `spctl -a` still rejected it, and `syspolicy_check distribution` reported
"Adhoc Signed App" and "Notary Ticket Missing" (fatal). Homebrew sets `com.apple.quarantine` on
every cask install, so every brew install hit the error. Fix: a `postflight` in
`Casks/gander.rb` runs `xattr -dr com.apple.quarantine` on the installed app. CI only `sed`s the
`version`/`sha256` lines, so the block survives cask updates. A tap push is enough: no release.
Existing installs need `brew reinstall --cask gander`. The full fix is Developer ID signing plus
notarization (paid Apple Developer account).

### logic-test.sh `named preset width` depended on the attached display count (2026-10-08)

Takeaway: tests that call `initialFrame(on:)` read the live `NSScreen.screens.count`, so they
must not hard-code `screenCount: 1`. With two displays attached, the `frameAuto` rule for one
screen never matched, the config fell back to legacy width, and `release.sh` aborted at the
logic-test step. Fix: the test rule uses `screenCountMin: 1`.

### `sitesCommand` — external site lists (DEVONthink) (2026-10-14)

Takeaway: Gander stays tool-agnostic. It runs a shell command and reads `name`/`url` from a
JSON array, instead of talking to DEVONthink itself. The `llm` instance uses
`~/🍇/Scripts/apps/dt/listBookmarks <group-uuid>`, the same script the Alfred `,` workflow uses.

- **PATH:** an app launched by launchd gets `/usr/bin:/bin:/usr/sbin:/sbin` only. The sd scripts
  need Homebrew tools and `/sbin/md5`; `env -i … PATH=/usr/bin:/bin` reproduced
  "md5 is not installed". `runSitesCommand` prepends Homebrew and sbin paths.
- **Refresh point:** the command reruns when the picker opens, not on a timer. The result
  arrives async, so `SitePickerView.configure` now reapplies the typed query and reloads the
  table. Before, `configure` reset `filtered` without `reloadData`, a latent stale-table bug
  that also hit `setTransientShortcut` while the picker was open.
- **Upstream cache bug (fixed in Scripts):** `listBookmarks` validated its cache against the
  DT group's `modification date as string`. Recent macOS puts U+202F (narrow no-break space)
  before AM/PM, no `date -jf` format matched, the timestamp fell back to 0, and the cache
  never expired on DT edits. The fix asks AppleScript for the age in seconds instead.
- **Verification without screen recording:** read the picker rows through the AX API
  (`AXUIElementCreateApplication(pid)` → walk `AXStaticText`). System Events reported
  0 windows for the non-activating panel. CGWindowList gives the frame.

## TASK-5: the sites shortcut always hit the default instance (fixed, 2026-10-28)

- **Cause:** `HotkeysConfig` fills a missing key with its default. `default.json` sets only `prev`
  and `next`, so the default instance registered `cmd+shift+\` and `cmd+shift+/` as global Carbon
  hotkeys. `llm.json` sets all four to `null`. A global hotkey belongs to one process and
  cannot follow the focused panel. Carbon also takes the key before any local `NSEvent` monitor,
  so a local monitor added beside it never ran.
- **Fix:** removed Carbon. All four chords are local, matched in `SidebarPanel`'s key monitor
  against `config.hotkeys` by physical key code (`parseHotkey` / `hotkeyMatches` in `Config.swift`)
  while the panel is key. Both instances can use the same chords. Cost: no chord works while
  another app is frontmost or the panel is hidden. Use the CLI, `gander://` or BetterTouchTool.
- **llm picker list:** `sitesCommand` output replaces `sites` only on success. On failure the
  4 static llm sites stay. A 10-row picker with Phind, Anna's Archive and MDN is the default picker.
- **Cold start (code):** the init path calls `openURL(config.defaultUrl)` and `pickerVisible`
  starts false, so no code path opens the picker or leaves the page blank. Not reproduced.
- **Open:** DEVONthink Apple Events authorization for the launchd llm instance is unverified.
  Terminal runs of `listBookmarks` fail with "Not authorized".

---

## Ur Browse sections (2026-11-03)

Everything below was written during the rename to Ur Browse and the UrKit refactor
(commits a9bf3ff and df9ef79).

### Socket IPC replaces DistributedNotificationCenter

**What happened.** The Gander CLI posted a notification and slept 150 ms. It could not ask anything
("which sites do you have?", "what page is showing?"), could not report an error from the app, had
no exit codes, and could not tell whether a pot was running. Notification names also embedded the
instance name, so every new verb needed a new name and a new observer.

**Root cause.** DistributedNotificationCenter is fire-and-forget broadcast, not a request/reply
channel. That is fine for toggle, useless for addressable sites and `--json`.

**Decision.** Each pot owns a Unix socket, `~/Library/Application Support/Ur/run/browse/<pot>.sock`
(`UR_RUN_DIR` overrides the root). Wire format: one JSON `Request` plus `\n` in, one JSON `Response`
plus `\n` out, then close. Consequences:
- Request/reply: `current`, `sites --json`, `info` return data; errors from the app come back to the
  shell with exit code 1.
- Liveness: `connect` succeeds if and only if the pot is running. The CLI exits **2** with "pot is not
  running — start it with …" for other verbs, and starts the pot for `autostartVerbs`
  (`toggle show open site picker`).
- A second launch of a running pot fails to claim the socket and exits 0, which ends the old
  "two default instances" LaunchAgent / Open-at-Login problem.
- No sleep. Not sandbox-compatible either (neither was the old transport).
- Socket paths have a 104-byte limit (`sun_path`), which is why pot names are limited to 40 characters.

### Pots and per-pot WKWebsiteDataStore (cookies were shared across instances)

**What happened.** Two Gander instances (`default`, `llm`) were not independent after all: both
processes shared one bundle id, so they shared WebKit's default website data store. Logging in to a
site in one logged you in to the other, and a "work" and a "personal" instance could never hold
different accounts.

**Root cause.** `WKWebsiteDataStore.default()` is keyed by bundle id, not by process.

**Fix.** Every pot uses `WKWebsiteDataStore(forIdentifier: pot.storageIdentifier)`, where the UUID
is derived deterministically from `ur.<app>.<pot>` (so it is stable without storing anything).
`ephemeral: true` in a pot's config uses `.nonPersistent()` instead — the smoke tests run on
that. Cost: after upgrading from Gander everyone logs in again once, because the old data stayed in
the default store.

Pot layout: `~/.config/ur/browse/<pot>/config.json` and `slip/`; LaunchAgent label
`io.ur.browse.<pot>`. `throw` writes the config (optionally `--from` another pot), creates `slip/`,
and with `--login` installs and bootstraps the LaunchAgent. `main.swift` still understands
`--config <file>` (old LaunchAgents, smoke tests) and uses the file's `name` as the pot; for
`--pot`/folder launches the folder name wins. First start copies `~/.config/gander/<name>.json` into
the pot folder (the original stays).

### URL scheme events go to an arbitrary process of the bundle → forward to the target pot's socket

**What happened.** With several pots running, `open -g "ur-browse://work/site/gh"` sometimes acted
on the wrong pot or did nothing. Previously the name inside the notification routed it; with URLs,
LaunchServices decides which process gets the Apple Event.

**Root cause.** All pots are processes of one bundle. LaunchServices delivers a URL to one of them —
not necessarily the pot named in the URL.

**Fix.** `AppDelegate.handleURL` parses the URL into a `Request`; if `request.pot` is this process's
pot it handles it, otherwise it sends the request to the target pot's socket on a background queue.
A URL for a stopped pot whose verb is in `autostartVerbs` (`open`, `site`, `show`, `toggle`,
`picker`) starts that pot first (`NSWorkspace.openApplication` with
`createsNewApplicationInstance = true` and `--pot <name>`; a dev build spawns its binary), waits up
to 8 s for its socket, then forwards. Other verbs for a stopped pot are dropped with a stderr
message. Side effect: if no pot was running at all, LaunchServices first launches the default pot
to receive the URL, and it stays running.

### Single-module logic tests and #if canImport(UrKit)

**What happened.** `logic-test.sh` compiles with plain `swiftc` (works with Command Line Tools, no
SwiftPM), so it cannot link modules. After the split into UrKit / UrBrowseSpec / the app, the app
files had `import UrKit` that does not exist when everything is compiled together.

**Decision.** `logic-test.sh` compiles `Sources/UrKit/*.swift`, `BrowseSpec.swift` and the pure app
files (Config, FrameLayout, SiteStore, BrowseCommand, Slip, Replies) plus the test runner into
**one module**. Every file that is shared this way wraps its cross-module imports:

```swift
#if canImport(UrKit)
import UrKit
#endif
```

SwiftPM builds still see the real modules. Rules: keep logic that needs tests in AppKit-free (or
only Config-level AppKit) files; add new pure files to the list in `logic-test.sh`; keep source
paths relative (absolute paths break CI, see the older gotcha). The smoke test covers what the
logic test can't — real socket, real pot, isolated by `UR_CONFIG_HOME`, `UR_RUN_DIR` and `ephemeral`.

### Rename to Ur Browse (what changed for users)

- Names: app `Ur Browse.app`, CLI `ur-browse`, bundle id `io.ur.browse`, macOS 14+. Gander stays as
  the nickname and the goose stays.
- Schemes: `ur-browse://` and legacy `gander://` both registered; the Cask installs `ur-browse`
  and a `gander` alias, both symlinks to `Contents/MacOS/ur-browse-cli` (the `-cli` suffix is still
  needed for the APFS case-collision reason above, and the same "dangling symlink" failure applies).
- Cask `ur-browse`; `cask_renames.json` maps `gander` → `ur-browse`; release zip is
  `UrBrowse-vX.Y.Z.zip`. The repo is renamed `o-o-o-o-o/gander` → `o-o-o-o-o/ur-browse` (redirects).
- Config moved to `~/.config/ur/browse/<pot>/config.json`, copied from `~/.config/gander/<name>.json`
  on first start; `color` → `glaze` (old key read).
- Cookies reset once (per-pot data store). Old LaunchAgents (`io.gander.*.plist`) pass `--config`
  and keep working but should be replaced with `ur-browse <pot> start --login`, which writes (or
  updates) a LaunchAgent for an existing pot; `throw --login` does the same for a new one.
- `build.sh` and `build-release.sh` share `scripts/bundle.sh`, so the local and CI bundle layout
  can no longer drift (the original `build.sh`-without-CLI bug, see above).
- New in the CLI: `pots`, `throw`, `start`, `site`, `sites --json|--alfred|--list`, `current`, `info`,
  `slip`. Bare `sites` still means "toggle the picker" for old bindings.

### Slip user scripts design

**Goal.** Per-pot Greasemonkey-style customization (hide a banner, tweak a docs site) without
making users edit the app.

**Decisions.**
- Plain files: `~/.config/ur/browse/<pot>/slip/*.js` and `*.css`, loaded in file-name order. Other
  files (`.off`, README, dotfiles) are ignored — rename to disable.
- Header lines in any comment style (`//`, `/* */`, `*`): `@name`, `@match`/`@include`, `@exclude`,
  `@run-at` (`document-start` | `document-end`, `document-idle` = end), `@all-frames`, `@noframes`.
  JS defaults to document-end, CSS to document-start. No `@match` = every page. No `GM_*` APIs.
- Matching is done in the page, not by WebKit's match patterns: `Slip.wrappedSource()` wraps each
  file in an IIFE that tests `location.href` against regexes generated from the globs (`*` is
  anything; `*.` right after `://` also matches the bare domain; `<all_urls>`). The same regex
  logic runs in Swift (`applies(to:)`) so logic-test can check it. Doing it in the page keeps
  SPA navigations and subframes correct with one `WKUserScript` per file.
- CSS is injected as a `<style data-slip="file">` by the same wrapper; JS gets
  `//# sourceURL=slip/<file>` so it is findable in the inspector.
- `ur-browse <pot> slip` reloads (no restart); `slip --list` shows what is loaded. `info --json`
  lists the slip files too.


## Pot dies with SIGPIPE on the first IPC request (TASK-6)

The pot exited with status 141 when the CLI sent its first request; the CLI printed
`no reply from …sock`, and the app left no log and no crash report. `SO_NOSIGPIPE` is set on the
accepted fd, but a write to a closed pipe elsewhere still raised SIGPIPE and the default action
killed the process. Fix: `signal(SIGPIPE, SIG_IGN)` in `IPCServer.start` (UrKit), so every Ur app
gets it. Diagnose by running the binary in the foreground and reading `$?`: 141 = 128 + SIGPIPE.
