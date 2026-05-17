import Foundation

// Edit this file to update the Help panel content.
// HTML is rendered by WKWebView; light/dark mode is handled by the CSS prefers-color-scheme query.
enum HelpContent {
    static func html(name: String, toggleKey: String, sitesKey: String,
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
        <img src="greg.png" alt="Gander" onerror="this.style.display='none'">
        <h1>Gander</h1>
        </div>

        <h2>Keyboard Shortcuts</h2>
        <table>
        <tr><td>\#(toggleKey)</td><td>Toggle sidebar</td></tr>
        <tr><td>\#(sitesKey)</td><td>Open site picker</td></tr>
        <tr><td>\#(nextKey)</td><td>Next site</td></tr>
        <tr><td>\#(prevKey)</td><td>Previous site</td></tr>
        <tr><td>⌘R</td><td>Reload page</td></tr>
        <tr><td>⌘⇧O</td><td>Open current page in external browser</td></tr>
        <tr><td>⌘1 – ⌘9</td><td>Jump to pinned site (when configured)</td></tr>
        </table>
        <p style="margin-top:10px"><strong>In site picker</strong></p>
        <table>
        <tr><td>↑ ↓</td><td>Navigate list</td></tr>
        <tr><td>↩</td><td>Open selected site</td></tr>
        <tr><td>⎋</td><td>Dismiss</td></tr>
        <tr><td>(type)</td><td>Filter by name or URL — typing a bare URL opens it directly</td></tr>
        </table>

        <h2>CLI</h2>
        <pre>gander \#(name) toggle
        gander \#(name) show / hide
        gander \#(name) sites                  open site picker
        gander \#(name) next / prev
        gander \#(name) open &lt;url&gt;
        gander \#(name) open &lt;url&gt; --shortcut &lt;1–9&gt;
        gander \#(name) frame --x &lt;n&gt; --y &lt;n&gt; --width &lt;n&gt; --height &lt;n&gt;
        gander menubar                         restore hidden menu bar icon</pre>
        <p class="dim" style="margin-top:4px">Examples</p>
        <pre>gander \#(name) open https://github.com/search?q=swift
        gander \#(name) open https://example.com --shortcut 3
        gander \#(name) frame --x 0 --y 0 --width 420 --height 900</pre>

        <h2>URL Scheme</h2>
        <pre>gander://\#(name)/toggle
        gander://\#(name)/show
        gander://\#(name)/show?x=&lt;n&gt;&amp;y=&lt;n&gt;&amp;width=&lt;n&gt;&amp;height=&lt;n&gt;
        gander://\#(name)/hide
        gander://\#(name)/sites
        gander://\#(name)/open?url=&lt;encoded-url&gt;
        gander://\#(name)/open?url=&lt;encoded-url&gt;&amp;shortcut=&lt;1–9&gt;
        gander://\#(name)/frame?x=&lt;n&gt;&amp;y=&lt;n&gt;&amp;width=&lt;n&gt;&amp;height=&lt;n&gt;</pre>
        <p class="dim">Shell: <code>open -g "gander://\#(name)/toggle"</code></p>
        <p class="dim">AppleScript: <code>open location "gander://\#(name)/toggle"</code></p>

        <h2>Pinned Shortcuts (⌘1–⌘9)</h2>
        <p>Set <code>"pinned"</code> in your config:</p>
        <table style="margin-top:8px">
        <tr><td>"auto"</td><td>First 9 sites get ⌘1–⌘9 in list order</td></tr>
        <tr><td>"manual"</td><td>Assign per site with a <code>"shortcut"</code> field (1–9)</td></tr>
        </table>
        <p class="dim" style="margin-top:8px">Transient — overrides config for that slot until restart:</p>
        <pre>gander \#(name) open https://example.com --shortcut 7
        open -g "gander://\#(name)/open?url=https%3A%2F%2Fexample.com&amp;shortcut=7"</pre>

        <h2>Config &nbsp;<span class="dim">~/.config/gander/\#(name).json</span></h2>
        <pre>{
          "name":            "\#(name)",
          "color":           "#4A90D9",    // accent stripe colour
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
            { "name": "Example", "url": "https://example.com" },
            { "name": "Search",  "url": "https://google.com/search?q=" },
            { "name": "Pinned",  "url": "https://github.com", "shortcut": 2 }
          ]
        }</pre>
        <p class="dim">Search sites: the typed query is appended to the URL.</p>
        <p class="dim" style="margin-top:4px">Multiple instances: give each a unique name + config, launch with
        <code>GanderApp --config ~/.config/gander/&lt;name&gt;.json</code></p>

        </body>
        </html>
        """#
    }
}
