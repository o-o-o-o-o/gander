# Gander — Project Learnings

Everything discovered while building and iterating on Gander. Organized for fast re-onboarding
and to avoid repeating the same mistakes.

*Note: this is a first Swift/macOS native app. The "AppKit Fundamentals" section below captures
patterns that experienced AppKit developers take for granted but that are non-obvious when
coming from other platforms.*

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

### How the `gander://` URL Scheme Works

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

If neither, Gatekeeper blocks launch and shows "cannot be opened because it is from an
unidentified developer." The user can override via System Settings → Privacy & Security.

Since Gander is unsigned and unnotarized, Homebrew's Cask caveats instruct users to remove
the quarantine attribute manually after install, or approve the app via System Settings:

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
