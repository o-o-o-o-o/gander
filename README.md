# 🪿 Gander

*Gander* as in "to take a gander" — a glimpse, a glance, a peek.

*Gander* as in a goose.

A floatable, hot key-able, native sidebar browser (NSPanel + WKWebView) that persists across all spaces (mac native and aerospace-like window managers).

---

## Why?

I wanted a dedicated and scriptable browser that gets out of my way when I want it to. I am using it to refer to documentation. I use it with Devonthink Pro and Alfred.app. HONK.

## Build & run

```bash
cd /Users/why/🍇/Applications/Gander
bash publish.sh        # build, logic-test, smoke-test → ./Gander.app
make publish           # same workflow, shorter entry point
open Gander.app
```

For a named instance (see Multiple instances below):

```bash
.build/release/GanderApp --config ~/.config/gander/work.json &
```

---

## Config file

Sites, color, window frame, and default URL are set in a JSON file.

**Default location:** `~/.config/gander/default.json`  
If this file exists it is loaded automatically on launch. Otherwise built-in defaults are used.

**Format:**

```json
{
  "name": "default",
  "color": "#4A90D9",
  "width": 420,
  "height": 877,
  "x": 1020,
  "y": 38,
  "defaultUrl": "https://google.com",
  "sites": [
    { "name": "Google", "url": "https://google.com" },
    { "name": "GitHub", "url": "https://github.com" },
    { "name": "Hacker News", "url": "https://news.ycombinator.com" },
    { "name": "YouTube", "url": "https://youtube.com" }
  ]
}
```

All fields are optional — omit any you don't need. `name` defaults to `"default"`.

| Field        | Type   | Description                                                   |
| ------------ | ------ | ------------------------------------------------------------- |
| `name`       | string | Instance identifier. Used for CLI routing.                    |
| `color`      | string | Hex color for the accent stripe + menu bar icon.              |
| `width`      | number | Window width in points. Default: 420.                         |
| `height`     | number | Window height in points. Default: visible screen height.      |
| `x`          | number | Left edge in screen points. Default: right edge placement.    |
| `y`          | number | Bottom edge in screen points. Default: visible screen bottom. |
| `defaultUrl` | string | URL loaded on first launch.                                   |
| `sites`      | array  | Site list shown in the picker (⌘⇧/).                          |

If `height`, `x`, or `y` are omitted, Gander preserves the current default behavior: full visible screen height, aligned to the right edge, starting at the bottom of the visible screen.

When you open a URL that is not already listed in `sites`, Gander adds it to the picker temporarily and labels it as temporary. If the URL matches a configured site, Gander reuses that configured entry instead of creating a duplicate.

---

## Keyboard shortcuts

| Shortcut  | Action                                        |
| --------- | --------------------------------------------- |
| `⌘⇧\`     | Toggle sidebar                                |
| `⌘⇧/`     | Open site picker (fuzzy search)               |
| `⌘⇧]`     | Next site                                     |
| `⌘⇧[`     | Previous site                                 |
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

```bash
gander toggle
gander show
gander show --width 480 --height 900
gander hide
gander open https://example.com
gander frame --x 80 --y 40 --width 420 --height 1000

# Named instance
gander work toggle
gander work open https://github.com --width 500
```

`show` and `open` accept optional `--x`, `--y`, `--width`, and `--height` overrides. `frame` updates only the window placement and size.

Can be called from shell scripts, Makefiles, or any tool that runs shell commands.

**AppleScript:**

```applescript
do shell script "gander toggle"
do shell script "gander work open https://example.com"
```

---

## URL scheme `gander://`

Works when running as the registered `.app` bundle (built via `build.sh`).

```
gander://toggle
gander://show
gander://show?width=480&height=900
gander://hide
gander://open?url=https%3A%2F%2Fexample.com&x=80&y=40&width=420&height=1000
gander://frame?x=80&y=40&width=420&height=1000
```

Named instance routing uses the first path component:

```
gander://work/toggle
gander://work/open?url=https%3A%2F%2Fgithub.com
```

**Shell:**

```bash
open -g "gander://toggle"
open -g "gander://work/open?url=https://github.com&width=500"
```

**BetterTouchTool / Alfred / Raycast:** use the `open` URL action with `gander://toggle` etc.

---

## Multiple instances

Each instance is a separate process launched with its own config file.

**Example: two instances running simultaneously**

`~/.config/gander/work.json`:

```json
{
  "name": "work",
  "color": "#2ECC71",
  "sites": [
    { "name": "Notion", "url": "https://notion.so" },
    { "name": "Linear", "url": "https://linear.app" }
  ]
}
```

`~/.config/gander/personal.json`:

```json
{
  "name": "personal",
  "color": "#E74C3C",
  "sites": [
    { "name": "Twitter", "url": "https://twitter.com" },
    { "name": "Reeder", "url": "https://reederapp.com" }
  ]
}
```

Launch both:

```bash
.build/release/GanderApp --config ~/.config/gander/work.json &
.build/release/GanderApp --config ~/.config/gander/personal.json &
```

Control each independently:

```bash
gander work toggle
gander personal open https://twitter.com
```

Each instance shows its color as a stripe below the toolbar and as a tint on its menu bar icon.

---

## Rebuild after changes

```bash
bash publish.sh --open
```

Use [BUILD_WORKFLOW.md](BUILD_WORKFLOW.md) as the short operational checklist for local build, logic-test, smoke-test, `gander://toggle` verification, and publish.

## Install and upgrades

Homebrew:

```bash
brew tap o-o-o-o-o/gander
brew install --cask gander
brew update && brew upgrade --cask gander   # pull a new release
```

Or download `Gander-vX.Y.Z.zip` from [GitHub Releases](https://github.com/o-o-o-o-o/gander/releases). Maintainer release steps: [RELEASE.md](RELEASE.md).

## Acknowledgments

Helped by 🤖s. HONK. HONK.