import AppKit
import Foundation

// Hotkey strings use the format "cmd+shift+\\" — modifiers are cmd/shift/option/ctrl,
// key is a single character or name (f1–f12, space, return, left, right, up, down).
// Set a key to null or "" to disable it.
struct HotkeysConfig: Codable {
    var toggle: String? = "cmd+shift+\\"
    var sites:  String? = "cmd+shift+/"
    var next:   String? = "cmd+shift+]"
    var prev:   String? = "cmd+shift+["

    enum CodingKeys: String, CodingKey { case toggle, sites, next, prev }

    init(toggle: String? = "cmd+shift+\\", sites: String? = "cmd+shift+/",
         next: String? = "cmd+shift+]", prev: String? = "cmd+shift+[") {
        self.toggle = toggle; self.sites = sites; self.next = next; self.prev = prev
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func field(_ key: CodingKeys, def: String?) -> String? {
            guard c.contains(key) else { return def }
            // present but null → nil (disabled); present with string → use it (empty = disabled)
            guard let v = try? c.decodeIfPresent(String.self, forKey: key), !v.isEmpty else { return nil }
            return v
        }
        toggle = field(.toggle, def: "cmd+shift+\\")
        sites  = field(.sites,  def: "cmd+shift+/")
        next   = field(.next,   def: "cmd+shift+]")
        prev   = field(.prev,   def: "cmd+shift+[")
    }
}

struct SiteConfig: Codable {
    var name: String
    var url: String
    var temporary: Bool
    var shortcut: Int?  // 1–9; used in manual pinned mode only; values outside range are ignored

    enum CodingKeys: String, CodingKey { case name, url, temporary, shortcut }

    init(name: String, url: String, temporary: Bool = false, shortcut: Int? = nil) {
        self.name = name
        self.url = url
        self.temporary = temporary
        self.shortcut = shortcut
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        url = try c.decode(String.self, forKey: .url)
        temporary = (try? c.decode(Bool.self, forKey: .temporary)) ?? false
        let raw = try? c.decode(Int.self, forKey: .shortcut)
        shortcut = raw.flatMap { (1...9).contains($0) ? $0 : nil }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(url, forKey: .url)
        if temporary { try c.encode(temporary, forKey: .temporary) }
        if let s = shortcut { try c.encode(s, forKey: .shortcut) }
    }
}

struct FrameConfig {
    var x: Double?
    var y: Double?
    var width: Double?
    var height: Double?

    var isEmpty: Bool {
        x == nil && y == nil && width == nil && height == nil
    }
}

struct AppConfig: Codable {
    var name: String
    var color: String?       // hex, e.g. "#4A90D9"
    var width: Double
    var height: Double?
    var x: Double?
    var y: Double?
    var defaultUrl: String
    var chrome: Bool            // false = no title bar or toolbar, keyboard-only nav
    var stripeHeight: Double    // height of the color stripe in points; 0 = no stripe
    var externalBrowser: String // app name or bundle ID, default "Safari"
    var pinned: String?         // nil = no shortcuts | "auto" = ⌘1–9 for first 9 sites | "manual" = per-site shortcut field
    var hotkeys: HotkeysConfig
    var sites: [SiteConfig]

    // All fields optional in JSON — everything has a sane default
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name         = (try? c.decode(String.self,          forKey: .name))         ?? "default"
        color        =  try? c.decode(String.self,          forKey: .color)
        width        = (try? c.decode(Double.self,          forKey: .width))        ?? 420
        height       =  try? c.decode(Double.self,          forKey: .height)
        x            =  try? c.decode(Double.self,          forKey: .x)
        y            =  try? c.decode(Double.self,          forKey: .y)
        defaultUrl   = (try? c.decode(String.self,          forKey: .defaultUrl))   ?? "https://google.com"
        chrome          = (try? c.decode(Bool.self,            forKey: .chrome))          ?? true
        stripeHeight    = (try? c.decode(Double.self,          forKey: .stripeHeight))    ?? 3
        externalBrowser = (try? c.decode(String.self,          forKey: .externalBrowser)) ?? "Safari"
        let rawPinned   =  try? c.decode(String.self,          forKey: .pinned)
        pinned          = rawPinned.flatMap { ["auto", "manual"].contains($0) ? $0 : nil }
        hotkeys      = (try? c.decode(HotkeysConfig.self,   forKey: .hotkeys))      ?? HotkeysConfig()
        sites        = (try? c.decode([SiteConfig].self,    forKey: .sites))        ?? AppConfig.builtinSites
    }

    init(name: String = "default", color: String? = nil, width: Double = 420,
         height: Double? = nil, x: Double? = nil, y: Double? = nil,
         defaultUrl: String = "https://google.com", chrome: Bool = true,
         stripeHeight: Double = 3, externalBrowser: String = "Safari",
         pinned: String? = nil, hotkeys: HotkeysConfig = HotkeysConfig(),
         sites: [SiteConfig] = AppConfig.builtinSites) {
        self.name = name; self.color = color; self.width = width
        self.height = height; self.x = x; self.y = y
        self.defaultUrl = defaultUrl; self.chrome = chrome
        self.stripeHeight = stripeHeight; self.externalBrowser = externalBrowser
        self.pinned = pinned; self.hotkeys = hotkeys; self.sites = sites
    }

    static let builtinSites: [SiteConfig] = [
        .init(name: "Google",       url: "https://google.com"),
        .init(name: "GitHub",       url: "https://github.com"),
        .init(name: "Hacker News",  url: "https://news.ycombinator.com"),
        .init(name: "YouTube",      url: "https://youtube.com"),
        .init(name: "Reddit",       url: "https://reddit.com"),
    ]

    var sidebarWidth: CGFloat { CGFloat(width) }

    var accentColor: NSColor? {
        guard let hex = color else { return nil }
        return NSColor(hex: hex)
    }

    // Notification names are scoped per instance so multiple instances coexist
    var notifToggle: Notification.Name { .init("com.gander.\(name).toggle") }
    var notifShow:   Notification.Name { .init("com.gander.\(name).show") }
    var notifHide:   Notification.Name { .init("com.gander.\(name).hide") }
    var notifOpen:   Notification.Name { .init("com.gander.\(name).open") }
    var notifFrame:  Notification.Name { .init("com.gander.\(name).frame") }
    var notifSites:  Notification.Name { .init("com.gander.\(name).sites") }
    var notifNext:    Notification.Name { .init("com.gander.\(name).next") }
    var notifPrev:    Notification.Name { .init("com.gander.\(name).prev") }
    var notifMenuBar: Notification.Name { .init("com.gander.\(name).menubar") }

    func initialFrame(on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let resolvedWidth = CGFloat(width)
        let resolvedHeight = CGFloat(height ?? visible.height)
        let resolvedX = CGFloat(x ?? (visible.maxX - resolvedWidth))
        let resolvedY = CGFloat(y ?? visible.minY)
        return NSRect(x: resolvedX, y: resolvedY, width: resolvedWidth, height: resolvedHeight)
    }

    static func load(from path: String) throws -> AppConfig {
        let expanded = (path as NSString).expandingTildeInPath
        let data = try Data(contentsOf: URL(fileURLWithPath: expanded))
        return try JSONDecoder().decode(AppConfig.self, from: data)
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h = String(h.dropFirst()) }
        guard h.count == 6, let v = UInt64(h, radix: 16) else { return nil }
        self.init(red:   CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >>  8) & 0xFF) / 255,
                  blue:  CGFloat( v        & 0xFF) / 255,
                  alpha: 1)
    }
}

func canonicalURLString(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard var comps = URLComponents(string: trimmed),
          let scheme = comps.scheme?.lowercased(),
          let host = comps.host?.lowercased() else {
        return trimmed
    }

    comps.scheme = scheme
    comps.host = host

    if (scheme == "https" && comps.port == 443) || (scheme == "http" && comps.port == 80) {
        comps.port = nil
    }
    if comps.path.isEmpty {
        comps.path = "/"
    }

    return comps.string ?? trimmed
}
