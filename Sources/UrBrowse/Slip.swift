import Foundation

/// Slip: per-pot user scripts and styles, Greasemonkey-style.
///
/// Every `*.js` and `*.css` file in `~/.config/ur/browse/<pot>/slip/` is injected into the pot's
/// pages, in file-name order. Anything else in the folder (e.g. `wip.js.off`, a README) is
/// ignored. Optional header lines, in any comment, control where and when a file runs:
///
///     // ==UserScript==
///     // @name     Quiet GitHub
///     // @match    https://github.com/*
///     // @match    *://*.example.com/*      ("*." after "://" also matches the bare domain)
///     // @exclude  https://github.com/settings/*
///     // @run-at   document-start          (JS default: document-end; CSS default: document-start)
///     // @all-frames                       (default: main frame only)
///     // ==/UserScript==
///
/// No @match / @include means every page. GM_* APIs are not provided.
struct SlipScript: Equatable {
    enum Kind: String { case js, css }
    enum RunAt: String { case documentStart = "document-start", documentEnd = "document-end" }

    let file: String
    let kind: Kind
    let source: String
    let name: String
    let matches: [String]
    let excludes: [String]
    let runAt: RunAt
    let allFrames: Bool

    static func load(from directory: URL) -> [SlipScript] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: directory.path) else { return [] }
        return files.sorted().compactMap { file in
            guard !file.hasPrefix("."),
                  let source = try? String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8)
            else { return nil }
            return parse(file: file, source: source)
        }
    }

    /// Nil for files that are neither .js nor .css.
    static func parse(file: String, source: String) -> SlipScript? {
        let ext = (file as NSString).pathExtension.lowercased()
        guard let kind = Kind(rawValue: ext) else { return nil }
        var name = (file as NSString).deletingPathExtension
        var matches: [String] = []
        var excludes: [String] = []
        var runAt: RunAt = kind == .css ? .documentStart : .documentEnd
        var allFrames = false

        for raw in source.split(whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            for prefix in ["//", "/*", "*"] where line.hasPrefix(prefix) {
                line = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
            guard line.hasPrefix("@") else { continue }
            if line.hasSuffix("*/") { line = String(line.dropLast(2)).trimmingCharacters(in: .whitespaces) }
            let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            let key = String(parts[0].dropFirst()).lowercased()
            let value = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
            switch key {
            case "name" where !value.isEmpty:    name = value
            case "match", "include":             if !value.isEmpty { matches.append(value) }
            case "exclude", "exclude-match":     if !value.isEmpty { excludes.append(value) }
            case "run-at":
                if value == "document-start" { runAt = .documentStart }
                else if value == "document-end" || value == "document-idle" { runAt = .documentEnd }
            case "all-frames":                   allFrames = true
            case "noframes":                     allFrames = false
            default: break
            }
        }
        return SlipScript(file: file, kind: kind, source: source, name: name, matches: matches,
                          excludes: excludes, runAt: runAt, allFrames: allFrames)
    }

    /// Glob → anchored JS/ICU regex source. `*` matches anything; `*.` directly after "://"
    /// matches any subdomain or none; `<all_urls>` matches everything.
    static func regex(forGlob glob: String) -> String {
        if glob == "<all_urls>" || glob == "*" { return "^.*$" }
        let chars = Array(glob)
        var out = "^"
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "*" {
                if String(chars[..<i]).hasSuffix("://"), i + 1 < chars.count, chars[i + 1] == "." {
                    out += "(?:[^/]*\\.)?"
                    i += 2
                    continue
                }
                out += ".*"
            } else if "\\^$.|?+()[]{}/".contains(c) {
                out += "\\" + String(c)
            } else {
                out.append(c)
            }
            i += 1
        }
        return out + "$"
    }

    /// Swift-side check with the same semantics as the injected JS guard (used by tests).
    func applies(to url: String) -> Bool {
        func hit(_ globs: [String]) -> Bool {
            globs.contains { url.range(of: Self.regex(forGlob: $0), options: .regularExpression) != nil }
        }
        if !matches.isEmpty && !hit(matches) { return false }
        return !hit(excludes)
    }

    private static func jsString(_ s: String) -> String {
        guard let data = try? JSONEncoder().encode(s), let out = String(data: data, encoding: .utf8) else { return "\"\"" }
        return out
    }

    /// The source wrapped in a URL guard (and, for CSS, a <style> injector).
    func wrappedSource() -> String {
        let m = matches.map { "/\(Self.regex(forGlob: $0))/" }.joined(separator: ",")
        let x = excludes.map { "/\(Self.regex(forGlob: $0))/" }.joined(separator: ",")
        let guardJS = """
            var __u = location.href, __m = [\(m)], __x = [\(x)];
            if (__m.length && !__m.some(function (r) { return r.test(__u); })) return;
            if (__x.some(function (r) { return r.test(__u); })) return;
            """
        switch kind {
        case .js:
            return "(function () {\n\(guardJS)\n\(source)\n})();\n//# sourceURL=slip/\(file)\n"
        case .css:
            return """
                (function () {
                \(guardJS)
                var s = document.createElement('style');
                s.setAttribute('data-slip', \(Self.jsString(file)));
                s.textContent = \(Self.jsString(source));
                (document.head || document.documentElement).appendChild(s);
                })();
                """
        }
    }

    var info: SlipInfo {
        SlipInfo(file: file, name: name, kind: kind.rawValue, matches: matches, excludes: excludes,
                 runAt: runAt.rawValue, allFrames: allFrames)
    }
}
