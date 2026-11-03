import Foundation
#if canImport(UrKit)
import UrKit
#endif

/// Typed form of every verb Ur Browse answers. `init(_:)` is the single place requests are
/// validated, whatever surface they came from (CLI, socket, `ur-browse://` URL), so a bad
/// option fails the same way everywhere and the CLI gets a real non-zero exit.
enum BrowseCommand: Equatable {
    case toggle
    case show(FrameConfig)
    case hide
    case picker
    case next
    case prev
    case open(url: String, shortcut: Int?, frame: FrameConfig)
    case site(id: String, path: String?, frame: FrameConfig)
    case listSites
    case current
    case frame(FrameConfig)
    case menubar
    case reloadSlip
    case listSlip
    case info
    case quit

    private static let frameKeys: Set<String> = ["preset", "x", "y", "width", "height"]
    /// Accepted on every verb: `format` is set by the CLI's --json / --alfred.
    private static let globalKeys: Set<String> = ["format"]

    init(_ r: Request) throws {
        func allow(_ keys: Set<String> = []) throws {
            for key in r.options.keys.sorted() where !keys.contains(key) && !Self.globalKeys.contains(key) {
                throw UrError("unknown option '--\(key)' for '\(r.verb)'")
            }
        }
        func maxArgs(_ n: Int) throws {
            if r.args.count > n { throw UrError("unexpected argument '\(r.args[n])' for '\(r.verb)'") }
        }
        let frame = FrameConfig(preset: r.option("preset"), x: r.option("x"), y: r.option("y"),
                                width: r.option("width"), height: r.option("height"))

        switch r.verb {
        case "toggle":  try allow(); try maxArgs(0); self = .toggle
        case "hide":    try allow(); try maxArgs(0); self = .hide
        case "picker":  try allow(); try maxArgs(0); self = .picker
        case "next":    try allow(); try maxArgs(0); self = .next
        case "prev":    try allow(); try maxArgs(0); self = .prev
        case "current": try allow(); try maxArgs(0); self = .current
        case "menubar": try allow(); try maxArgs(0); self = .menubar
        case "info":    try allow(); try maxArgs(0); self = .info
        case "quit":    try allow(); try maxArgs(0); self = .quit

        case "show":
            try allow(Self.frameKeys); try maxArgs(0)
            self = .show(frame)

        case "sites":
            // Bare `sites` keeps its Gander meaning (toggle the picker); asking for a listing
            // (--list, --json, --alfred) returns the addressable site list instead.
            try allow(["list"]); try maxArgs(0)
            self = (r.flag("list") || r.option("format") != nil) ? .listSites : .picker

        case "open":
            try allow(Self.frameKeys.union(["url", "shortcut"])); try maxArgs(1)
            guard let url = r.args.first ?? r.option("url") else { throw UrError("'open' requires a URL") }
            var shortcut: Int? = nil
            if let raw = r.option("shortcut") {
                guard let n = Int(raw), (1...9).contains(n) else {
                    throw UrError("'--shortcut' requires a number between 1 and 9")
                }
                shortcut = n
            }
            self = .open(url: url, shortcut: shortcut, frame: frame)

        case "site":
            // CLI: `site gh/o-o-o-o-o/ur-browse`; URL: ur-browse://work/site/gh/o-o-o-o-o/ur-browse
            // arrives as separate path segments — both join back into "id/path".
            try allow(Self.frameKeys.union(["id", "path"]))
            let joined = (r.args.isEmpty ? [r.option("id") ?? ""] : r.args).joined(separator: "/")
            let parts = joined.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            guard let first = parts.first, !first.isEmpty else {
                throw UrError("'site' requires a site id (list them with: ur-browse sites --list)")
            }
            var path = parts.count > 1 ? String(parts[1]) : nil
            if let p = r.option("path") { path = p }
            self = .site(id: String(first), path: (path?.isEmpty ?? true) ? nil : path, frame: frame)

        case "frame":
            try allow(Self.frameKeys); try maxArgs(1)
            var f = frame
            if let preset = r.args.first { f.preset = preset }
            guard !f.isEmpty else {
                throw UrError("'frame' requires a preset name or at least one of --x, --y, --width, --height")
            }
            self = .frame(f)

        case "slip":
            try allow(["list"]); try maxArgs(0)
            self = r.flag("list") ? .listSlip : .reloadSlip

        default:
            throw UrError("unknown command '\(r.verb)'")
        }
    }
}
