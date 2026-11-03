# 🪿 Ur Browse

*Gander* as in "to take a gander" — a glimpse, a glance, a peek. *Gander* as in a goose.
The goose and the nickname stay; the app is now **Ur Browse**, the first app of the **Ur** suite
(ur-mail and ur-notes will follow).

A floatable, hot key-able, native sidebar browser (NSPanel + WKWebView) that persists across all
spaces (mac native and aerospace-like window managers). macOS 14+.

---

## Why?

I wanted a dedicated and scriptable browser that gets out of my way when I want it to. I am using it to refer to documentation. I use it with Devonthink Pro and Alfred.app. HONK.

Every site has an address, so anything that can run a shell command or open a URL can say
"show me *this* page, in *that* browser, now".

## Install

Homebrew:

```bash
brew tap o-o-o-o-o/ur-browse
brew install --cask ur-browse
brew update && brew upgrade --cask ur-browse   # pull a new release
```

The repo is being renamed `o-o-o-o-o/gander` → `o-o-o-o-o/ur-browse`; GitHub redirects the old
URLs, so old taps and links keep working. Or download `UrBrowse-vX.Y.Z.zip` from
[GitHub Releases](https://github.com/o-o-o-o-o/ur-browse/releases) and drag `Ur Browse.app` to
`/Applications`. Maintainer release steps: [RELEASE.md](RELEASE.md).

The Cask installs two CLI names pointing at the same binary: `ur-browse` and the legacy `gander`.

Ur Browse is not signed with an Apple Developer certificate. The Cask strips the quarantine flag; if
macOS still blocks it:

```bash
xattr -dr com.apple.quarantine "/Applications/Ur Browse.app"
# or: System Settings → Privacy & Security → Open Anyway
```

---

## Lexicon

The Ur suite uses a ceramics vocabulary. The same words are used in the code, the CLI and these docs.

| Word | Meaning |
| ---- | ------- |
| **Ur** | The suite. Addresses look like `<app>://<pot>/<kind>/<id>`. |
| **clay** | The app template / source: the shared skeleton (UrKit + UrAppSpec) every Ur app is made from. |
| **pot** | An instance of an app: its own config, slip scripts, website data (cookies, logins), socket and optional LaunchAgent. Replaces the word "instance". |
| **throw** | Create a pot: `ur-browse throw work --glaze '#2ECC71' --login`. |
| **glaze** | A pot's look: config key `glaze`, a hex color (progress bar + menu bar tint). |
| **slip** | User scripts and styles in the pot's `slip/` folder. |
| **kiln** | Build, test and promote: `publish.sh`, the agent loop. |

---

## Pots

One app, many pots. Each pot is a separate process with its own folder:

```
~/.config/ur/browse/<pot>/config.json     settings and sites
~/.config/ur/browse/<pot>/slip/           user scripts and styles
```

plus its own website data store (a pot is a true single-site-browser: logins in one pot are not
visible in another), its own Unix socket, and optionally a LaunchAgent. The default pot is named
`default`.

```bash
ur-browse throw work --glaze '#2ECC71' --login   # create the pot, start it at login
ur-browse throw play --from work --no-start      # copy another pot's config, don't start it
ur-browse pots                                   # list pots and whether they run
ur-browse pots --json
ur-browse work start                             # start a stopped pot
ur-browse work toggle
ur-browse work quit
```

`throw <pot> [--glaze #hex] [--url u] [--from pot] [--login] [--no-start]`:

- writes `~/.config/ur/browse/<pot>/config.json` (and the `slip/` folder);
- `--from` copies another pot's config first, `--glaze` and `--url` (the `defaultUrl`) override it;
- `--login` installs and loads a LaunchAgent (`~/Library/LaunchAgents/io.ur.browse.<pot>.plist`) so
  the pot starts at login; otherwise the pot is started now unless `--no-start`.

Pot names: letters, digits, `-` and `_`, at most 40 characters, not a command name.

Running pots:

- A second launch of an already-running pot exits quietly, so a LaunchAgent and "Open at Login"
  can never leave two copies of the same pot. (The menu's "Open at Login" registers only the
  default pot, so the menu item only appears there; use `start --login` for the others.)
- `open`, `site`, `show`, `toggle` and `picker` start a stopped pot automatically. Other commands
  fail with **exit code 2** ("pot is not running"). Other errors exit 1.
- Hotkeys are local: a pot answers a chord only while its own panel is key, so pots can share the
  same chords. Show/hide from outside goes through the CLI, a URL, or a key bound in another tool
  to `ur-browse <pot> toggle`.
- Each pot shows its glaze as the page-load progress bar and as a tint on its menu bar icon.

Under the hood the CLI talks to the pot over a per-pot Unix socket
(`~/Library/Application Support/Ur/run/browse/<pot>.sock`) — request/reply, so the CLI gets real
answers and real exit codes. `UR_CONFIG_HOME` and `UR_RUN_DIR` override the two roots (used by the
tests for isolated pots).

---

## Config file

`~/.config/ur/browse/<pot>/config.json`. All fields are optional. If the file does not exist,
built-in defaults are used.

```json
{
  "name": "work",
  "glaze": "#2ECC71",
  "width": 420,
  "defaultUrl": "https://google.com",
  "sites": [
    { "id": "gh", "name": "GitHub", "url": "https://github.com" },
    { "name": "Hacker News", "url": "https://news.ycombinator.com" },
    { "name": "Notion", "url": "https://notion.so", "shortcut": 1 }
  ]
}
```

| Field             | Type    | Description |
| ----------------- | ------- | ----------- |
| `name`            | string  | Pot name. The folder name wins if they differ. |
| `glaze`           | string  | Hex color for the top progress bar + menu bar icon. `color` is still accepted. |
| `width`           | number  | Window width in points. Default: 420. |
| `height`          | number  | Window height in points. Default: visible screen height. |
| `x`               | number  | Left edge in screen points. Default: right edge placement. |
| `y`               | number  | Bottom edge in screen points. Default: visible screen bottom. |
| `frame`           | string  | Name of the active frame preset. |
| `frames`          | object  | Named frame presets (see below). |
| `frameAuto`       | object  | Rules that pick a preset by display count. |
| `defaultUrl`      | string  | URL loaded on launch and with ⌘0. Default: `https://google.com`. |
| `chrome`          | bool    | `false` = no title bar or toolbar, keyboard-only navigation. Default: `true`. |
| `stripeHeight`    | number  | Height of the top progress bar in points; `0` disables it. Default: 2. |
| `externalBrowser` | string  | App name or bundle ID for ⌘⇧O. Default: `Safari`. |
| `pinned`          | string  | `"auto"` = ⌘1–9 for the first 9 sites; `"manual"` = per-site `shortcut`; omit for none. |
| `hotkeys`         | object  | `toggle`, `sites`, `next`, `prev` chords such as `"cmd+shift+\\"`. `null` or `""` disables one. |
| `sites`           | array   | Site list shown in the picker (⌘⇧/). Each entry: `id` (optional), `name`, `url`, `shortcut` (1–9, optional). |
| `sitesCommand`    | string  | Shell command that prints a JSON array of `{name, url}` (and optionally `id`). Replaces `sites` when it succeeds. |
| `ephemeral`       | bool    | `true` = in-memory website data, nothing persisted (used by the smoke tests). Default: `false`. |

If `height`, `x`, or `y` are omitted: full visible screen height, aligned to the right edge,
starting at the bottom of the visible screen.

Hotkey format: `"modifier+modifier+key"` with modifiers `cmd`, `shift`, `option`/`alt`, `ctrl`.

### Sites from a command (DEVONthink, etc.)

Set `sitesCommand` to load the site list from another tool. The command runs with `/bin/zsh -c` at
launch and each time the site picker opens, and prints a JSON array to stdout. `name` and `url`
(and an optional `id`, string or number) are read from each entry; other keys are ignored.

```json
{
  "sitesCommand": "\"$HOME/🍇/Scripts/apps/dt/listBookmarks\" 8DFC550E-5F2F-4020-8EE2-A4C19F334E5C"
}
```

- Homebrew and `/usr/sbin` are added to `PATH`, because apps launched from the Dock get a minimal `PATH`.
- If the command fails, times out (15 s), or prints an empty list, the current list is kept. Keep `sites` as a fallback.
- `pinned: "auto"` follows the command order, so ⌘1–⌘9 map to its first nine entries.

### Named frames (laptop / studio)

Use `frames` for presets and `frameAuto` to switch when displays are connected or disconnected.
Sizes can be points (`420`) or percentages (`"30%"`, `"100%"`, `"full"`). Position can be points,
`"right"` / `"bottom"`, etc.

```json
{
  "frame": "studio",
  "frames": {
    "laptop": { "width": "30%", "height": "100%", "x": "right", "y": "bottom" },
    "studio": { "width": 420, "height": "100%", "x": "right", "y": "bottom" }
  },
  "frameAuto": {
    "match": [
      { "screenCount": 1, "frame": "laptop" },
      { "screenCountMin": 2, "frame": "studio" }
    ]
  }
}
```

When the display layout changes (dock / undock), the matching preset is applied on the **main**
screen (menu bar display). Legacy top-level `width` / `height` / `x` / `y` still work as a
`"default"` preset when `frames` is omitted.

When you open a URL that is not already listed in `sites`, it is added to the picker temporarily and
labelled as temporary. If the URL matches a configured site, that entry is reused.

---

## Sites and addressability

Every site has an **id**. It is what you use to point at a site from the shell, a URL, Alfred,
BetterTouchTool, DEVONthink — anything.

- An explicit `id` in the config is kept as written.
- Otherwise the id is a slug of the name: `Hacker News` → `hacker-news` (ASCII letters and digits,
  runs of anything else become one dash; `site` if nothing survives). Temporary sites use a slug of
  the host.
- Collisions get `-2`, `-3`, … in list order. Ids are stable as long as the config order is, so set
  explicit ids for anything you bind to.
- Lookup is forgiving: exact id, then case-insensitive id, then name.

```bash
ur-browse work site gh                          # show the site "gh"
ur-browse work site gh/o-o-o-o-o/ur-browse      # deep link: github.com + /o-o-o-o-o/ur-browse
open -g "ur-browse://work/site/gh"              # same, as a URL
open -g "ur-browse://work/site/gh/o-o-o-o-o/ur-browse"

ur-browse work sites --list                     # human-readable list
ur-browse work sites --json                     # machine-readable
ur-browse work sites --alfred                   # Alfred Script Filter JSON
ur-browse work current --json                   # active site, URL, title
ur-browse pots --json
ur-browse work info --json
```

`site <id>/<path>` appends the path to the site's URL (a path starting with `?` or `#` is appended
as-is). Every site carries a canonical `address`, `ur-browse://<pot>/site/<id>`. The pot is always
spelled out, so the address means the same thing from anywhere.

`sites --json` returns, per site: `id`, `name`, `url`, `shortcut`, `temporary`, `open` (has a live
page), `active`, `address`. `current --json` returns `pot`, `site`, `name`, `url` (the page actually
loaded, possibly deeper than the site's URL), `title`, `visible`, `address`. These field names are an
automation contract.

URLs for another pot are forwarded to it. `open`, `site`, `show`, `toggle` and `picker` start a
stopped pot before sending, so bindings never have to care whether it is running.

### Alfred Script Filter

Script Filter, language `/bin/zsh`, with the query passed as argv:

```bash
/opt/homebrew/bin/ur-browse work sites --alfred
```

Each item has `uid` (the site id), `title` (the name), `subtitle` (the URL), `autocomplete` and `arg`
(the site's `ur-browse://work/site/<id>` address). Connect the filter to an **Open URL** action on
`{query}` and picking a site shows it. `ur-browse pots --alfred` lists pots the same way.

---

## Slip

Slip = user scripts and styles, Greasemonkey-style. Every `*.js` and `*.css` file in
`~/.config/ur/browse/<pot>/slip/` is injected into the pot's pages, in file-name order. Anything
else in the folder (`wip.js.off`, a README, dotfiles) is ignored. Optional header lines, in any
comment, control where and when a file runs:

```js
// ==UserScript==
// @name     Quiet GitHub
// @match    https://github.com/*
// @match    *://*.example.com/*      ("*." after "://" also matches the bare domain)
// @exclude  https://github.com/settings/*
// @run-at   document-start          (JS default: document-end; CSS default: document-start)
// @all-frames                       (default: main frame only)
// ==/UserScript==
```

- `@match` / `@include` and `@exclude` take globs where `*` matches anything; `<all_urls>` matches
  every page. With no `@match`, a file runs on every page.
- `@run-at` is `document-start` or `document-end` (`document-idle` counts as `document-end`).
- `@all-frames` also injects into subframes; `@noframes` restores the default.
- `GM_*` APIs are not provided.

Example, `slip/quiet-github.css`:

```css
/* ==UserScript==
   @name   Quiet GitHub
   @match  https://github.com/*
   ==/UserScript== */
.footer, .js-notice { display: none !important; }
```

Apply changes without restarting the pot:

```bash
ur-browse work slip            # reload slip scripts
ur-browse work slip --list     # what is loaded, with match rules
```

---

## Keyboard shortcuts

| Shortcut  | Action                                        |
| --------- | --------------------------------------------- |
| `⌘⇧\`     | Toggle sidebar                                |
| `⌘⇧/`     | Open site picker (fuzzy search)               |
| `⌘⇧]`     | Next site                                     |
| `⌘⇧[`     | Previous site                                 |
| `⌘0`      | Open `defaultUrl`                             |
| `⌘1`–`⌘9` | Jump to pinned site (when `pinned` is set)   |
| `⌘R`      | Reload page (when sidebar is focused)         |
| `⌘⇧O`     | Open current page in external browser         |
| `⌘[`      | Back (when webview focused)                   |
| `⌘]`      | Forward (when webview focused)                |

**In site picker:**

| Shortcut | Action                                                    |
| -------- | --------------------------------------------------------- |
| `↑ ↓`   | Navigate list                                             |
| `↩`      | Open selected site                                        |
| `Esc`    | Dismiss                                                   |
| (type)   | Filter by name or URL — a bare URL or domain opens it directly |

Toolbar buttons (back, forward, sites) are always clickable regardless of focus.

---

## CLI

`ur-browse` (alias `gander`). Omit `[pot]` for the default pot.

```
Usage: ur-browse [pot] <command> [args] [options]

Pots:
  ur-browse pots [--json]                  list pots and whether they are running
  ur-browse throw <pot> [--glaze #hex] [--url u] [--from pot] [--login] [--no-start]
  ur-browse <pot> start [--login]          start a stopped pot (--login: also at login)
  ur-browse <pot> quit

Window:
  ur-browse [pot] toggle | show | hide     (show takes frame options)
  ur-browse [pot] frame <preset> | frame --x v --y v --width v --height v
  ur-browse [pot] menubar                  restore a hidden menu bar icon

Sites (addressable by id):
  ur-browse [pot] site <id>[/path]         open a site, optionally deep-linked
  ur-browse [pot] sites --json | --alfred | --list
  ur-browse [pot] picker                   toggle the site picker (also: bare `sites`)
  ur-browse [pot] next | prev
  ur-browse [pot] open <url> [--shortcut 1-9]
  ur-browse [pot] current [--json]         active site, URL and title

Slip (user scripts in ~/.config/ur/browse/<pot>/slip/):
  ur-browse [pot] slip [--list]            reload slip scripts (or list them)

  ur-browse [pot] info --json

Frame values: points (420), percent (30%), or full/100%; --x/--y also take
left/right/top/bottom.
```

Examples:

```bash
ur-browse toggle
ur-browse show --width 480 --height 900
ur-browse open https://example.com
ur-browse frame laptop
ur-browse frame --width 30% --height 100%
ur-browse frame --x 80 --y 40 --width 420 --height 1000
ur-browse work open https://github.com --width 500
ur-browse work open https://example.com --shortcut 3   # transient ⌘3 for this run
```

`show`, `open` and `site` accept `--x`, `--y`, `--width` and `--height` overrides. `frame` applies a
named preset or partial overrides. `--json` / `--alfred` can be added to any command that returns
data.

Exit codes: 0 ok, 1 error (bad option, unknown site, …), 2 the pot is not running (and the command
does not autostart).

AppleScript:

```applescript
do shell script "ur-browse toggle"
do shell script "ur-browse work site gh"
```

---

## URL scheme

`ur-browse://` (and the legacy `gander://`) — both are registered, so old bindings keep working.
Works when running as the registered `.app` bundle.

```
ur-browse://[pot/]<command>[/args…][?option=value]

ur-browse://toggle
ur-browse://show?width=480&height=900
ur-browse://work/site/gh
ur-browse://work/site/gh/o-o-o-o-o/ur-browse
ur-browse://work/open?url=https%3A%2F%2Fgithub.com&width=500
ur-browse://work/frame?x=80&y=40&width=420&height=1000
```

The first path component is the pot when it is not a command name. All pots share one bundle, so
macOS hands the URL to an arbitrary running process of it; that process forwards it to the target
pot's socket. Like the CLI, `open`, `site`, `show`, `toggle` and `picker` URLs start a stopped
pot first; other verbs for a stopped pot are dropped with a message on stderr.

```bash
open -g "ur-browse://toggle"
open -g "ur-browse://work/open?url=https://github.com&width=500"
```

**BetterTouchTool / Alfred / Raycast:** use the `open` URL action with `ur-browse://toggle` etc.

---

## Build & run

```bash
cd path/to/ur-browse
bash publish.sh        # build, logic-test, smoke-test → "./Ur Browse.app"
make publish           # same workflow, shorter entry point
open "Ur Browse.app"
```

Run a named pot from a dev build:

```bash
.build/release/UrBrowseApp --pot work &
.build/release/ur-browse work toggle
```

`bash publish.sh --open` rebuilds and opens. Use [BUILD_WORKFLOW.md](BUILD_WORKFLOW.md) as the short
checklist for local build, logic-test, smoke-test, `ur-browse://toggle` verification, and publish.
Contributor notes: [CONTRIBUTING.md](CONTRIBUTING.md).

---

## Upgrading from Gander

- **Config.** On first start, a pot with no config in the new place copies
  `~/.config/gander/<name>.json` to `~/.config/ur/browse/<name>/config.json`. The old file is left
  alone. `color` is still read as `glaze`.
- **CLI.** The Cask installs `ur-browse` and a legacy `gander` alias, and `gander://` still works,
  so existing shell, BetterTouchTool and Alfred bindings keep working. Move to `ur-browse` at
  leisure.
- **Cookies reset.** Every pot now has its own website data store (before, all instances shared one),
  so you log in to your sites once again after upgrading.
- **LaunchAgents.** Old agents (`~/Library/LaunchAgents/io.gander.*.plist`) pass `--config` and
  still work, but should be replaced:

  ```bash
  launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/io.gander.work.plist
  rm ~/Library/LaunchAgents/io.gander.*.plist
  ur-browse work start --login     # LaunchAgent for the (migrated) existing pot
  ```

  The new agent is `io.ur.browse.<pot>.plist`; re-running `start --login` updates it.
- **Homebrew.** The tap maps the old cask name through `cask_renames.json`; if `brew upgrade` does
  not pick it up, run `brew install --cask ur-browse`.

## Acknowledgments

Helped by 🤖s. HONK. HONK.
