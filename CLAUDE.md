# urBrowse — Claude Code Context

## What this is

**urBrowse** (nickname Gander, the goose) — a floating sidebar browser for macOS 14+ (NSPanel +
WKWebView), the first app of the **ur** suite (ur-mail and ur-notes will follow). App
`urBrowse.app`, CLI `ur-browse` (legacy alias `gander`), URL schemes `ur-browse://` and legacy
`gander://`, bundle id `io.ur.browse`. Controlled by hotkeys, the CLI, and URLs. No Xcode project —
built with `swift build` and shell scripts. The repo is being renamed `o-o-o-o-o/gander` →
`o-o-o-o-o/ur-browse` (GitHub redirects).

## Lexicon

Use these words in code, commit messages and docs. Never say "instance" — say **pot**.

- **ur** — the suite; address scheme `<app>://<pot>/<kind>/<id>`
- **clay** — the app template / source (UrKit + `UrAppSpec` is the reusable skeleton)
- **pot** — an instance: own config, slip scripts, website data store (cookies/logins), socket,
  optional LaunchAgent. Folder: `~/.config/ur/browse/<pot>/{config.json,slip/}`
- **throw** — create a pot (`ur-browse throw work --glaze '#2ECC71' --login`)
- **glaze** — a pot's look (config key `glaze`, hex color; `color` still accepted)
- **slip** — user scripts/styles in the pot's `slip/` folder
- **kiln** — build / test / promote (`publish.sh`, the agent loop)

## Build & run locally

```bash
bash publish.sh           # build + logic tests + smoke tests → "./urBrowse.app" (repo root)
bash publish.sh --open    # same, then opens it
bash logic-test.sh        # logic tests only
bash smoke-test.sh        # needs bash build.sh first (uses .build/release/ur-browse)
```

## Release

Full checklist: **[RELEASE.md](RELEASE.md)** (user upgrade + maintainer ship).

When asked to publish / release / ship — just do it, no confirmation needed:

```bash
git pull origin main
git tag --sort=-v:refname | head -1   # latest tag
bash scripts/release.sh 0.1.6         # patch = fix, minor = feature
gh run list --repo o-o-o-o-o/ur-browse --limit 3   # confirm CI + Release passed
git pull origin main                  # CI pushes Update Cask commit — pull it
```

`release.sh` requires a clean tree, runs logic tests, pushes `main`, then tags. CI failure on
Cask push has happened before (v0.1.5) if `main` was not pushed first. The release asset is
`UrBrowse-vX.Y.Z.zip`; the Cask is `Casks/ur-browse.rb`.

## Source layout

```
Sources/UrKit/          shared ur skeleton (Foundation only): Pot, Request/Response, IPC (Unix
                        socket), UrCLI + UrAppSpec (generic CLI: pots/throw/start/--json/--alfred)
Sources/UrBrowseSpec/   BrowseSpec — the one verb list + usage text + UrAppSpec for urBrowse
Sources/UrBrowse/       app (target UrBrowseApp): AppDelegate (one dispatcher for socket + URL
                        requests), BrowseCommand (typed verbs + validation), SidebarPanel,
                        SiteStore (ids, URL matching), Slip, Replies (--json payloads), Config,
                        FrameLayout, SitePicker, FindBar, HelpContent, main.swift
Sources/ur-browse-cli/  CLI (product ur-browse): just `UrCLI(BrowseSpec.spec).run()`
scripts/bundle.sh       assembles "urBrowse.app"; shared by build.sh and scripts/build-release.sh
scripts/release.sh      tag + push + trigger GitHub Actions
scripts/build-release.sh CI build: compile → bundle.sh → UrBrowse-vX.Y.Z.zip
build.sh                local dev build → "./urBrowse.app" (never copies to /Applications)
logic-test.sh           single-module compile of UrKit + UrBrowseSpec + pure app files; no app launch
smoke-test.sh           integration test: launches an isolated pot (temp config, socket, ephemeral data)
Casks/ur-browse.rb      Homebrew Cask (version + SHA256 auto-updated by CI); cask_renames.json: gander → ur-browse
```

## Adding a verb

Add it to `BrowseSpec.verbs` (+ usage text), a case in `BrowseCommand` (parsing/validation), and
handle it in `AppDelegate.execute`. Nothing else: the CLI, socket, URL scheme, `--json` plumbing and
autostart come from UrKit. Add logic tests for the parser. Update README, HelpContent.

## Key gotchas

- `canBecomeKey: Bool { true }` in SidebarPanel must not be removed — NSPanel with
  `.nonactivatingPanel` cannot receive keyboard events without it when `chrome: false`
  (no `.titled`, no toolbar). Removing it causes completely silent breakage.

- IPC is a per-pot Unix socket (`~/Library/Application Support/Ur/run/browse/<pot>.sock`,
  `UR_RUN_DIR` overrides), request/reply, one JSON request per connection. There is no sleep in
  the CLI any more. `connect` succeeding means "pot is running"; the server claims the socket at
  launch and a second launch of a running pot exits 0. CLI exit codes: 1 error, 2 pot not running.
  Verbs in `autostartVerbs` (`toggle show open site picker`) start a stopped pot first. Socket paths
  must stay under 104 bytes — hence the 40-character pot-name limit.

- URL-scheme events go to an arbitrary process of the bundle, not the pot named in the URL.
  `AppDelegate.handleURL` therefore forwards a URL for another pot to that pot's socket. Do not
  assume the receiving process is the target pot.

- Each pot has its own `WKWebsiteDataStore(forIdentifier: pot.storageIdentifier)`; `ephemeral: true`
  uses `.nonPersistent()` (smoke tests). Never share the default store between pots.

- `scripts/release.sh` pushes `main` before creating the tag — required so the Cask update
  commit at the end of CI can push back to `main` cleanly.

- `logic-test.sh` compiles UrKit, UrBrowseSpec and the pure app files into **one module** with
  `swiftc` (no `import UrKit` across modules). Any file it compiles must wrap `import UrKit` /
  `import UrBrowseSpec` in `#if canImport(UrKit)`, and must not use AppKit-only or app-only types
  unless the logic test already compiles them. Keep source paths relative (absolute paths break in
  CI). New pure file → add it to the list in `logic-test.sh`.

- The daily app is the **Homebrew install** at `/Applications/urBrowse.app`. The repo-root
  `build.sh` output is **test-only** — never copy it over `/Applications`. The Cask symlinks both
  `ur-browse` and `gander` → `Contents/MacOS/ur-browse-cli`; if an old/incomplete local build
  overwrites the brew copy, those symlinks dangle and every external trigger (CLI, URL scheme,
  BetterTouchTool) silently dies. Restore with `brew reinstall --cask ur-browse`.

- If a **global trigger like `fn + -` stops working**, it's almost certainly an external
  BetterTouchTool→`ur-browse`/`gander` CLI binding, not an app hotkey (`fn` isn't a Carbon
  modifier). Diagnose with `which ur-browse` / `ls -lL /opt/homebrew/bin/ur-browse` first.

- Shortcuts that hold **Shift**: use `event.characters(byApplyingModifiers: [])`, not
  `charactersIgnoringModifiers` — the latter still applies Shift (`⌘⇧[`→`"{"`). The empty
  modifier set recovers the base key directly (see SidebarPanel's local key monitor).

- Old LaunchAgents (`io.gander.*.plist`) pass `--config <file>`; `main.swift` still honours it. New
  ones are written by `ur-browse throw <pot> --login` as `io.ur.browse.<pot>.plist` with `--pot`.

## Reference implementations

`driceroland/Search` (github.com/driceroland/Search) — a comparable WKWebView-based macOS
browser, more mature (2.3k+ stars). Worth checking for implementation ideas on problems urBrowse
shares with it: WKWebView configuration, window/panel behavior, IPC, release tooling. Already
mined for the Shift-key fix above, pairing `canBecomeMain: false` with `canBecomeKey`, and the
CSS-injection idiom used to hide scrollbars. See `learnings.md` for what was checked and what
wasn't there (e.g. it does *not* hide scrollbars itself — that part isn't ported from it).

## Config file

`~/.config/ur/browse/<pot>/config.json` — all fields optional (`glaze`, `ephemeral`, site `id`,
…). Pre-rename `~/.config/gander/<name>.json` is copied there once on first start. See README.md
and `learnings.md` for the schema.

## Maintaining learnings.md

**Any time we discover something non-obvious during a session — a gotcha, a silent failure,
a design decision, a CI quirk, a workaround — add it to `learnings.md` immediately, before
moving on.** Do not wait until the end of the session; context is lost.

What counts:
- A bug that had a surprising root cause
- A build/CI failure and what fixed it
- An AppKit/macOS API behaving unexpectedly
- A design tradeoff we consciously chose

What does not count:
- Things already in learnings.md
- Obvious fixes (typos, missing nil checks)
- Implementation details already visible in the code

When adding to learnings.md, follow the existing format: name the section clearly, describe
what happened, explain the root cause, and say what the fix was. Future-you needs to
understand why without having to re-derive it.

## More detail

See `learnings.md` for architecture decisions, gotchas, and reuse as a template.
