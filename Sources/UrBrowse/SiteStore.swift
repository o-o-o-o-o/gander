import Foundation

/// The pot's site list: configured sites (from `sites` or `sitesCommand`), temporary sites
/// (opened by URL, not in the config), ⌘1–9 shortcuts, and stable ids for addressing.
///
/// Pure value logic — no AppKit, no web views — so logic-test.sh covers it directly.
/// `SidebarPanel` owns one and asks it every "which site is this?" question.
struct SiteStore {
    private(set) var configured: [SiteConfig] = []
    private(set) var temporary: [SiteConfig] = []
    private var transientShortcuts: [Int: String] = [:]  // runtime-only; set via `open --shortcut`
    let pinned: String?

    init(sites: [SiteConfig], pinned: String?) {
        self.pinned = pinned
        replaceConfigured(sites)
    }

    /// Configured first, then temporary — the picker and next/prev order. Every entry has an id.
    var all: [SiteConfig] { configured + temporary }

    mutating func replaceConfigured(_ sites: [SiteConfig]) {
        configured = sites.map { var s = $0; s.temporary = false; return s }
        reassignIDs()
    }

    // MARK: Ids

    /// "Hacker News" → "hacker-news". ASCII letters and digits survive; runs of anything else
    /// become one dash. Falls back to "site" when nothing survives (e.g. an all-emoji name).
    static func slug(_ text: String) -> String {
        var out = ""
        var pendingDash = false
        for scalar in text.lowercased().unicodeScalars {
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                if pendingDash && !out.isEmpty { out.append("-") }
                out.unicodeScalars.append(scalar)
                pendingDash = false
            } else {
                pendingDash = true
            }
        }
        return out.isEmpty ? "site" : out
    }

    /// Explicit ids are kept as written; derived ids are slugs of the name (temporary sites:
    /// of the host). Collisions get "-2", "-3", … in list order, so earlier entries keep the
    /// short id. Ids are therefore stable as long as the config order is.
    private mutating func reassignIDs() {
        var taken = Set<String>()
        func unique(_ base: String) -> String {
            var candidate = base
            var n = 2
            while taken.contains(candidate.lowercased()) { candidate = "\(base)-\(n)"; n += 1 }
            taken.insert(candidate.lowercased())
            return candidate
        }
        configured = configured.map { site in
            var s = site
            s.id = unique(site.id ?? Self.slug(site.name))
            return s
        }
        temporary = temporary.map { site in
            var s = site
            s.id = unique(Self.slug(site.name))
            return s
        }
    }

    /// Exact id, then case-insensitive id, then name (exact, case-insensitive, or same slug).
    func site(id query: String) -> SiteConfig? {
        let sites = all
        if let s = sites.first(where: { $0.id == query }) { return s }
        let lower = query.lowercased()
        if let s = sites.first(where: { $0.id?.lowercased() == lower }) { return s }
        if let s = sites.first(where: { $0.name.lowercased() == lower }) { return s }
        let slug = Self.slug(query)
        return sites.first { Self.slug($0.name) == slug }
    }

    // MARK: URL matching

    static func key(for urlString: String) -> String { canonicalURLString(urlString) }

    /// The site whose canonical URL equals `urlString`'s.
    func site(forURL urlString: String) -> SiteConfig? {
        let key = Self.key(for: urlString)
        return all.first { Self.key(for: $0.url) == key }
    }

    /// Exact canonical URL, then same host + path ignoring the query, so search URLs like
    /// `?q=term` are associated with their parent site entry.
    func site(matching urlString: String) -> SiteConfig? {
        if let exact = site(forURL: urlString) { return exact }
        guard let comps = URLComponents(string: urlString), let host = comps.host else { return nil }
        return all.first {
            guard let sc = URLComponents(string: $0.url), let sh = sc.host else { return false }
            return sh == host && sc.path == comps.path
        }
    }

    func index(of site: SiteConfig) -> Int? {
        let key = Self.key(for: site.url)
        return all.firstIndex { Self.key(for: $0.url) == key }
    }

    /// The existing site for `urlString`, or a new temporary one appended to the list.
    /// `added` tells the caller to refresh the picker.
    mutating func siteForOpening(urlString: String) -> (site: SiteConfig, added: Bool) {
        if let existing = site(forURL: urlString) { return (existing, false) }
        let host = URL(string: urlString)?.host
        let name = (host?.isEmpty == false) ? host! : urlString
        temporary.append(SiteConfig(name: name, url: urlString, temporary: true))
        reassignIDs()
        return (temporary.last!, true)
    }

    /// `base` + `path`: "https://github.com" + "o-o-o-o-o/ur-browse" → "https://github.com/o-o-o-o-o/ur-browse".
    /// A path starting with "?" or "#" is appended as-is.
    static func deepURL(base: String, path: String) -> String {
        if path.hasPrefix("?") || path.hasPrefix("#") { return base + path }
        var b = base
        while b.hasSuffix("/") { b.removeLast() }
        var p = Substring(path)
        while p.hasPrefix("/") { p = p.dropFirst() }
        return "\(b)/\(p)"
    }

    // MARK: Shortcuts (⌘1–⌘9)

    var hasShortcuts: Bool { pinned != nil || !transientShortcuts.isEmpty }

    /// "auto" → first 9 configured sites get ⌘1–⌘9 in order.
    /// "manual" → sites with a `shortcut` field; first occurrence wins on duplicates.
    var configShortcuts: [Int: SiteConfig] {
        switch pinned {
        case "auto":
            return Dictionary(uniqueKeysWithValues:
                configured.prefix(9).enumerated().map { ($0.offset + 1, $0.element) })
        case "manual":
            var result: [Int: SiteConfig] = [:]
            for site in configured {
                if let n = site.shortcut, result[n] == nil { result[n] = site }
            }
            return result
        default:
            return [:]
        }
    }

    /// url → shortcut number for the picker badges; transient shortcuts override config ones.
    func shortcutURLMap() -> [String: Int] {
        var result: [String: Int] = [:]
        for (n, site) in configShortcuts { result[site.url] = n }
        for (n, url) in transientShortcuts { result[url] = n }
        return result
    }

    mutating func setTransientShortcut(_ n: Int, url: String) {
        guard (1...9).contains(n) else { return }
        transientShortcuts[n] = url
        _ = siteForOpening(urlString: url)
    }

    mutating func site(forShortcut n: Int) -> SiteConfig? {
        if let url = transientShortcuts[n] { return siteForOpening(urlString: url).site }
        return configShortcuts[n]
    }
}
