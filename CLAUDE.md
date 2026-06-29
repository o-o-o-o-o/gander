# Gander — Claude Code Context

## What this is

A floating sidebar browser for macOS (NSPanel + WKWebView). Controlled by global hotkeys,
`gander` CLI, and `gander://` URL scheme. No Xcode project — built with `swift build` and
shell scripts.

## Build & run locally

```bash
bash publish.sh           # build + logic tests + smoke tests → ./Gander.app (repo root)
bash publish.sh --open    # same, then opens ./Gander.app
```

## Release

Full checklist: **[RELEASE.md](RELEASE.md)** (user upgrade + maintainer ship).

When asked to publish / release / ship — just do it, no confirmation needed:

```bash
git pull origin main
git tag --sort=-v:refname | head -1   # latest tag
bash scripts/release.sh 0.1.6         # patch = fix, minor = feature
gh run list --repo o-o-o-o-o/gander --limit 3   # confirm CI + Release passed
git pull origin main                  # CI pushes Update Cask commit — pull it
```

`release.sh` requires a clean tree, runs logic tests, pushes `main`, then tags. CI failure on
Cask push has happened before (v0.1.5) if `main` was not pushed first.

## Source layout

```
Sources/Gander/         app — AppDelegate, SidebarPanel, SitePicker, Config, FrameLayout, Help
Sources/gander-cli/     CLI tool — posts a DistributedNotificationCenter message and exits
scripts/release.sh      tag + push + trigger GitHub Actions
scripts/build-release.sh CI build: compile → bundle .app → zip
build.sh                local dev build → ./Gander.app (never copies to /Applications)
logic-test.sh           unit tests for Config.swift (no app launch required)
smoke-test.sh           integration test: launches isolated instance, exercises CLI
Casks/gander.rb         Homebrew Cask definition (version + SHA256 auto-updated by CI)
```

## Key gotchas

- `canBecomeKey: Bool { true }` in SidebarPanel must not be removed — NSPanel with
  `.nonactivatingPanel` cannot receive keyboard events without it when `chrome: false`
  (no `.titled`, no toolbar). Removing it causes completely silent breakage.

- `Thread.sleep(0.15)` at the end of the CLI is intentional — DistributedNotificationCenter
  delivery is async; the process must stay alive until the OS routes the notification.

- `scripts/release.sh` pushes `main` before creating the tag — required so the Cask update
  commit at the end of CI can push back to `main` cleanly.

- `logic-test.sh` must use relative source paths (`Sources/Gander/Config.swift`) — absolute
  paths break in CI.

- The daily app is the **Homebrew install** at `/Applications/Gander.app`. The repo-root
  `build.sh` output is **test-only** — never copy it over `/Applications`. `build.sh` bundles
  `gander-cli` (added v0.2.1); if an older/incomplete local build overwrites the brew copy, the
  Cask's `gander → Contents/MacOS/gander-cli` symlink goes dangling and every external trigger
  (CLI, `gander://`, BetterTouchTool) silently dies. Restore with `brew reinstall --cask gander`.

- If a **global trigger like `fn + -` stops working**, it's almost certainly an external
  BetterTouchTool→`gander` CLI binding, not a Gander hotkey (`fn` isn't a Carbon modifier).
  Diagnose with `which gander` / `ls -lL /opt/homebrew/bin/gander` first, not the hotkey code.

- Shortcuts that hold **Shift** must not compare against `charactersIgnoringModifiers` as-is:
  it keeps Shift, so `⌘⇧[`→`"{"`, `⌘⇧]`→`"}"`, `⌘⇧G`→`"G"`. Compare `.lowercased()` or by
  keyCode (see SidebarPanel's local key monitor).

## Config file

`~/.config/gander/default.json` — all fields optional. See `learnings.md` for full schema.

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
