import Foundation

// Edit this file to update the Help panel content.
// HTML is rendered by WKWebView; light/dark mode is handled by the CSS prefers-color-scheme query.
enum HelpContent {
    static func html(name: String, version: String, toggleKey: String, sitesKey: String,
                     nextKey: String, prevKey: String) -> String {
        #"""
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="color-scheme" content="light dark">
        <style>
        :root {
          --bg:      #ffffff;
          --text:    #1d1d1f;
          --dim:     #6e6e73;
          --code-bg: #f2f2f7;
          --border:  #d2d2d7;
        }
        @media (prefers-color-scheme: dark) {
          :root {
            --bg:      #1c1c1e;
            --text:    #f5f5f7;
            --dim:     #98989d;
            --code-bg: #2c2c2e;
            --border:  #3a3a3c;
          }
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
          font-family: -apple-system, BlinkMacSystemFont, sans-serif;
          font-size: 13px;
          line-height: 1.6;
          color: var(--text);
          background: var(--bg);
          padding: 24px 28px 36px;
        }
        h2 {
          font-size: 10.5px;
          font-weight: 700;
          letter-spacing: 0.07em;
          text-transform: uppercase;
          color: var(--dim);
          margin: 28px 0 8px;
          padding-bottom: 5px;
          border-bottom: 1px solid var(--border);
        }
        h2:first-of-type { margin-top: 2px; }
        .header { text-align: center; margin-bottom: 24px; }
        .header img {
          width: 72px; height: auto;
          display: block; margin: 0 auto 8px;
        }
        @media (prefers-color-scheme: dark) {
          .header img { filter: invert(1); opacity: 0.9; }
        }
        .header h1 { font-size: 15px; font-weight: 600; }
        p { margin: 5px 0; }
        strong { font-weight: 600; }
        .dim { color: var(--dim); font-size: 12px; }
        table { border-collapse: collapse; margin: 6px 0; }
        td { padding: 2px 16px 2px 0; vertical-align: top; }
        td:first-child {
          white-space: nowrap;
          font-family: ui-monospace, "SF Mono", Menlo, monospace;
          font-size: 12px;
          font-weight: 500;
          min-width: 120px;
        }
        code {
          font-family: ui-monospace, "SF Mono", Menlo, monospace;
          font-size: 12px;
          background: var(--code-bg);
          padding: 1px 5px;
          border-radius: 4px;
        }
        pre {
          font-family: ui-monospace, "SF Mono", Menlo, monospace;
          font-size: 12px;
          background: var(--code-bg);
          padding: 10px 14px;
          border-radius: 6px;
          margin: 8px 0;
          line-height: 1.65;
          overflow-x: auto;
        }
        </style>
        </head>
        <body>

        <div class="header">
        <img src="greg.png" alt="Ur Browse" onerror="this.style.display='none'">
        <h1>Ur Browse</h1>
        <p class="dim">Version \#(version) &middot; pot <code>\#(name)</code></p>
        <p class="dim">Gander, the goose. First app of the Ur suite.</p>
        </div>

        <h2>Lexicon</h2>
        <table>
        <tr><td>Ur</td><td>The suite. Addresses look like <code>&lt;app&gt;://&lt;pot&gt;/&lt;kind&gt;/&lt;id&gt;</code></td></tr>
        <tr><td>clay</td><td>The app template (shared skeleton every Ur app is made from)</td></tr>
        <tr><td>pot</td><td>An instance: own config, slip, logins, socket, optional LaunchAgent</td></tr>
        <tr><td>throw</td><td>Create a pot</td></tr>
        <tr><td>glaze</td><td>A pot's look (hex color)</td></tr>
        <tr><td>slip</td><td>User scripts and styles in the pot's <code>slip/</code> folder</td></tr>
        <tr><td>kiln</td><td>Build, test and promote</td></tr>
        </table>

        <h2>Keyboard Shortcuts</h2>
        <table>
        <tr><td>\#(toggleKey)</td><td>Toggle sidebar</td></tr>
        <tr><td>\#(sitesKey)</td><td>Open site picker</td></tr>
        <tr><td>\#(nextKey)</td><td>Next site</td></tr>
        <tr><td>\#(prevKey)</td><td>Previous site</td></tr>
        <tr><td>⌘R</td><td>Reload page</td></tr>
        <tr><td>⌘⇧O</td><td>Open current page in external browser</td></tr>
        <tr><td>⌘0</td><td>Open <code>defaultUrl</code> from config</td></tr>
        <tr><td>⌘1 – ⌘9</td><td>Jump to pinned site (when configured)</td></tr>
        </table>
        <p style="margin-top:10px"><strong>In site picker</strong></p>
        <table>
        <tr><td>↑ ↓</td><td>Navigate list</td></tr>
        <tr><td>↩</td><td>Open selected site</td></tr>
        <tr><td>⎋</td><td>Dismiss</td></tr>
        <tr><td>(type)</td><td>Filter by name or URL — typing a bare URL opens it directly</td></tr>
        </table>

        <h2>Pots</h2>
        <p>Each pot has its own folder <code>~/.config/ur/browse/&lt;pot&gt;/</code> (<code>config.json</code>
        and <code>slip/</code>), its own logins and cookies, and its own socket. Hotkeys are local to the
        pot whose panel is key.</p>
        <pre>ur-browse pots [--json]
        ur-browse throw work --glaze '#2ECC71' --login
        ur-browse throw play --from work --no-start
        ur-browse work start
        ur-browse work quit</pre>
        <p class="dim"><code>--login</code> starts the pot at login via a LaunchAgent. <code>open</code>,
        <code>site</code>, <code>show</code>, <code>toggle</code> and <code>picker</code> start a stopped pot
        automatically; other commands exit 2 when the pot is not running.</p>

        <h2>CLI</h2>
        <p class="dim">Command <code>ur-browse</code> (legacy alias <code>gander</code>). Omit the pot for <code>default</code>.</p>
        <pre>ur-browse \#(name) toggle | show | hide
        ur-browse \#(name) picker              toggle the site picker
        ur-browse \#(name) next | prev
        ur-browse \#(name) open &lt;url&gt; [--shortcut &lt;1–9&gt;]
        ur-browse \#(name) site &lt;id&gt;[/path]
        ur-browse \#(name) sites --json | --alfred | --list
        ur-browse \#(name) current [--json]
        ur-browse \#(name) frame &lt;preset&gt; [--x v --y v --width v --height v]
        ur-browse \#(name) slip [--list]
        ur-browse \#(name) info --json
        ur-browse \#(name) menubar             restore hidden menu bar icon</pre>
        <p class="dim" style="margin-top:4px">Examples</p>
        <pre>ur-browse \#(name) frame laptop
        ur-browse \#(name) frame --width 30% --height 100%
        ur-browse \#(name) open https://example.com --shortcut 3</pre>

        <h2>Sites &amp; Addresses</h2>
        <p>Every site has an id: the <code>"id"</code> in its config entry, otherwise a slug of its name
        (<code>Hacker News</code> → <code>hacker-news</code>). Use it from anywhere:</p>
        <pre>ur-browse \#(name) site gh
        ur-browse \#(name) site gh/o-o-o-o-o/ur-browse    deep link
        open -g "ur-browse://\#(name)/site/gh"
        ur-browse \#(name) sites --alfred                  Alfred Script Filter</pre>
        <p class="dim">URLs for another pot are forwarded to it. <code>--json</code> output includes each
        site's <code>address</code>, e.g. <code>ur-browse://\#(name)/site/gh</code>.</p>

        <h2>URL Scheme</h2>
        <pre>ur-browse://\#(name)/toggle
        ur-browse://\#(name)/show?x=&lt;n&gt;&amp;y=&lt;n&gt;&amp;width=&lt;n&gt;&amp;height=&lt;n&gt;
        ur-browse://\#(name)/hide
        ur-browse://\#(name)/picker
        ur-browse://\#(name)/site/&lt;id&gt;[/path]
        ur-browse://\#(name)/open?url=&lt;encoded-url&gt;
        ur-browse://\#(name)/open?url=&lt;encoded-url&gt;&amp;shortcut=&lt;1–9&gt;
        ur-browse://\#(name)/frame?x=&lt;n&gt;&amp;y=&lt;n&gt;&amp;width=&lt;n&gt;&amp;height=&lt;n&gt;</pre>
        <p class="dim">Shell: <code>open -g "ur-browse://\#(name)/toggle"</code></p>
        <p class="dim">AppleScript: <code>open location "ur-browse://\#(name)/toggle"</code></p>
        <p class="dim">The legacy <code>gander://</code> scheme still works.</p>

        <h2>Slip (user scripts)</h2>
        <p>Every <code>*.js</code> and <code>*.css</code> file in
        <code>~/.config/ur/browse/\#(name)/slip/</code> is injected into the pot's pages, in file-name order.
        Reload with <code>ur-browse \#(name) slip</code>.</p>
        <pre>// ==UserScript==
        // @name     Quiet GitHub
        // @match    https://github.com/*
        // @exclude  https://github.com/settings/*
        // @run-at   document-start     (JS default: document-end)
        // @all-frames                  (default: main frame only)
        // ==/UserScript==</pre>
        <p class="dim">No <code>@match</code> means every page. <code>GM_*</code> APIs are not provided.</p>

        <h2>Pinned Shortcuts (⌘1–⌘9)</h2>
        <p>Set <code>"pinned"</code> in your config:</p>
        <table style="margin-top:8px">
        <tr><td>"auto"</td><td>First 9 sites get ⌘1–⌘9 in list order</td></tr>
        <tr><td>"manual"</td><td>Assign per site with a <code>"shortcut"</code> field (1–9)</td></tr>
        </table>
        <p class="dim" style="margin-top:8px">Transient — overrides config for that slot until restart:</p>
        <pre>ur-browse \#(name) open https://example.com --shortcut 7
        open -g "ur-browse://\#(name)/open?url=https%3A%2F%2Fexample.com&amp;shortcut=7"</pre>

        <h2>Config &nbsp;<span class="dim">~/.config/ur/browse/\#(name)/config.json</span></h2>
        <pre>{
          "name":            "\#(name)",
          "glaze":           "#4A90D9",    // progress bar + menu bar tint ("color" still works)
          "width":           420,
          "height":          900,
          "x":               20,           // initial window position
          "y":               40,
          "defaultUrl":      "https://example.com",
          "chrome":          false,        // hide title bar / toolbar
          "externalBrowser": "Safari",     // app name or bundle ID for ⌘⇧O
          "pinned":          "auto",       // "auto" | "manual" | omit to disable
          "hotkeys": {
            "toggle": "cmd+shift+backslash",
            "sites":  "cmd+shift+slash",
            "next":   "cmd+shift+]",
            "prev":   "cmd+shift+["
          },
          "sites": [
            { "id": "ex", "name": "Example", "url": "https://example.com" },
            { "name": "Search",  "url": "https://google.com/search?q=" },
            { "name": "Pinned",  "url": "https://github.com", "shortcut": 2 }
          ]
        }</pre>
        <p class="dim">Search sites: the typed query is appended to the URL.</p>
        <p class="dim" style="margin-top:4px">Upgrading from Gander: configs in
        <code>~/.config/gander/&lt;name&gt;.json</code> are copied into the pot folder on first start. Each pot now
        has its own website data, so you log in to your sites once again.</p>

        </body>
        </html>
        """#
    }
}
