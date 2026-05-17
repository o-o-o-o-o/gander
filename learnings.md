# Gander — Project Learnings

Everything discovered while building and iterating on Gander. Organized for fast re-onboarding
and to avoid repeating the same mistakes.

---

## What Gander Is

A floating sidebar browser for macOS — an `NSPanel` containing a `WKWebView` that stays visible
across all Mission Control spaces and Aerospace window-manager spaces. Controlled by global hotkeys,
a CLI tool (`gander toggle`), and a `gander://` URL scheme. All three control paths route through
`NSDistributedNotificationCenter` so the CLI is just a thin messenger that posts one notification
and exits.

---

## Architecture

```
main.swift               parse --config, create AppConfig, run NSApplication
AppDelegate.swift        hotkeys (Carbon), IPC (DistributedNotificationCenter),
                         URL scheme (NSAppleEventManager), menu bar, help panel
SidebarPanel.swift       NSPanel subclass: WKWebView session pool, site picker,
                         keyboard shortcuts, external browser, frame control
SitePicker.swift         frosted-glass NSView with NSTableView + NSSearchField
Config.swift             AppConfig / SiteConfig / HotkeysConfig, canonicalURLString,
                         NSColor hex init
HelpContent.swift        self-contained HTML rendered in a WKWebView for the Help panel
Sources/gander-cli/      thin CLI: parse args, post one DistributedNotificationCenter
                         notification, sleep 150ms to let the OS deliver it, exit
```

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

### Carbon `RegisterEventHotKey` for global hotkeys

Alternatives considered: `CGEventTap` (requires Input Monitoring TCC permission, user dialog),
`NSEvent.addGlobalMonitorForEvents` (same permission), `MASShortcut` (external dependency).

Carbon `RegisterEventHotKey`:
- No Input Monitoring permission, no TCC dialog, no user friction
- System-wide from the moment the app launches
- Works in all macOS versions that support the Carbon Events framework
- Tradeoff: can't suppress the keypress — it still propagates to the frontmost app

The signature `0x47414E44` is the ASCII encoding of `GAND` — a stable 4-byte app identifier
required by the Carbon API. Arbitrary but must be unique per app.

### NSDistributedNotificationCenter for IPC

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

### Multiple instances

Each instance is a separate process launched with `GanderApp --config <path>`. The `name` field
in the config drives:
- All `DistributedNotificationCenter` notification names
- The `UserDefaults` key for the "hide menu bar icon" preference
- The `gander <name> <command>` CLI routing
- The `gander://<name>/action` URL scheme routing

No inter-instance coordination. Each instance is completely independent.

### Two `frameConfig` overload helpers in AppDelegate

`AppDelegate` has two private helpers with identical signatures returning a `FrameConfig`:
one reads from a `[AnyHashable: Any]?` userInfo dictionary (used by IPC notifications) and one
reads from `URLComponents?` query items (used by the `gander://` URL scheme). The duplication
avoids a shared extraction layer that would need to bridge the two formats — both callers are
one line each.

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
3. `bash build.sh` — full release bundle, installs to /Applications/Gander.app
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

### `nm` binary sanity check in build-release.sh

The release build checks `nm "$APP_BIN" | grep AppDelegate` to confirm the right binary was
built. Without this check, a wrong-product build can silently produce a `gander`-CLI-shaped
binary named `GanderApp` — which launches and exits immediately with no error.

---

## Config Schema Reference

```json
{
  "name":            "default",
  "color":           "#4A90D9",
  "width":           420,
  "height":          900,
  "x":               20,
  "y":               40,
  "defaultUrl":      "https://google.com",
  "chrome":          true,
  "stripeHeight":    3,
  "externalBrowser": "Safari",
  "pinned":          "auto",
  "hotkeys": {
    "toggle": "cmd+shift+\\",
    "sites":  "cmd+shift+/",
    "next":   "cmd+shift+]",
    "prev":   "cmd+shift+["
  },
  "sites": [
    { "name": "GitHub",  "url": "https://github.com" },
    { "name": "Pinned",  "url": "https://example.com", "shortcut": 1 }
  ]
}
```

All fields optional; defaults are sane. `pinned` accepts `"auto"` (⌘1–⌘9 for first 9 sites
in list order), `"manual"` (per-site `shortcut: 1–9` field), or omit to disable shortcuts.

Hotkey format: `"modifier+modifier+key"` where modifiers are `cmd`, `shift`, `option`/`alt`,
`ctrl`. Set to `null` or `""` to disable.

---

## Reuse as a Template

This project is a clean minimal template for no-Xcode NSPanel Mac apps. The pattern:
- No Xcode project, no provisioning, no Developer account required
- Carbon hotkeys (no TCC/Input Monitoring permission)
- NSDistributedNotificationCenter IPC between CLI and app
- Homebrew Cask distribution with automated SHA256 and version updates
- GitHub Actions CI/CD: build → artifact → Release → Cask update in one workflow

To fork for a new app: update `Package.swift` names, replace `Sources/Gander/` with your
source, replace `Sources/gander-cli/` with your CLI, update `Casks/gander.rb`, update
notification name prefix (`com.gander.`) and hotkey signature (`0x47414E44 / GAND`).
