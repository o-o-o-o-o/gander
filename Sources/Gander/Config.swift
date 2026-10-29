import AppKit
import Foundation

// Hotkey strings use the format "cmd+shift+\\" — modifiers are cmd/shift/option/ctrl,
// key is a single character or name (f1–f12, space, return, left, right, up, down).
// Set a key to null or "" to disable it. Hotkeys are local: they fire only while the
// instance's own panel is key (see SidebarPanel's key monitor).
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

struct AppConfig: Codable {
    var name: String
    var color: String?       // hex, e.g. "#4A90D9"
    var width: Double
    var height: Double?
    var x: Double?
    var y: Double?
    var frame: String?           // active preset name
    var frames: [String: FramePreset]?
    var frameAuto: FrameAutoConfig?
    var defaultUrl: String
    var chrome: Bool            // false = no title bar or toolbar, keyboard-only nav
    var stripeHeight: Double    // height of the top progress bar in points; 0 = disabled
    var externalBrowser: String // app name or bundle ID, default "Safari"
    var pinned: String?         // nil = no shortcuts | "auto" = ⌘1–9 for first 9 sites | "manual" = per-site shortcut field
    var hotkeys: HotkeysConfig
    var sites: [SiteConfig]
    var sitesCommand: String?   // shell command printing a JSON [{name,url}] array; replaces `sites` when it succeeds

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
        stripeHeight    = (try? c.decode(Double.self,          forKey: .stripeHeight))    ?? 2
        externalBrowser = (try? c.decode(String.self,          forKey: .externalBrowser)) ?? "Safari"
        let rawPinned   =  try? c.decode(String.self,          forKey: .pinned)
        pinned          = rawPinned.flatMap { ["auto", "manual"].contains($0) ? $0 : nil }
        hotkeys      = (try? c.decode(HotkeysConfig.self,   forKey: .hotkeys))      ?? HotkeysConfig()
        sites        = (try? c.decode([SiteConfig].self,    forKey: .sites))        ?? AppConfig.builtinSites
        sitesCommand = (try? c.decode(String.self,          forKey: .sitesCommand)).flatMap { $0.isEmpty ? nil : $0 }
        frame        = try? c.decode(String.self,            forKey: .frame)
        frames       = try? c.decode([String: FramePreset].self, forKey: .frames)
        frameAuto    = try? c.decode(FrameAutoConfig.self, forKey: .frameAuto)
    }

    init(name: String = "default", color: String? = nil, width: Double = 420,
         height: Double? = nil, x: Double? = nil, y: Double? = nil,
         frame: String? = nil, frames: [String: FramePreset]? = nil,
         frameAuto: FrameAutoConfig? = nil,
         defaultUrl: String = "https://google.com", chrome: Bool = true,
         stripeHeight: Double = 2, externalBrowser: String = "Safari",
         pinned: String? = nil, hotkeys: HotkeysConfig = HotkeysConfig(),
         sites: [SiteConfig] = AppConfig.builtinSites, sitesCommand: String? = nil) {
        self.name = name; self.color = color; self.width = width
        self.height = height; self.x = x; self.y = y
        self.frame = frame; self.frames = frames; self.frameAuto = frameAuto
        self.defaultUrl = defaultUrl; self.chrome = chrome
        self.stripeHeight = stripeHeight; self.externalBrowser = externalBrowser
        self.pinned = pinned; self.hotkeys = hotkeys; self.sites = sites
        self.sitesCommand = sitesCommand
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

    /// Preset used at launch: `frameAuto` match for current screen count, then `frame`, then legacy root fields.
    func launchPresetName(screenCount: Int) -> String {
        if let auto = frameAuto?.presetName(forScreenCount: screenCount) {
            return auto
        }
        if let frame { return frame }
        return "default"
    }

    func legacyDefaultPreset() -> FramePreset {
        var preset = FramePreset(width: .points(width))
        if let height { preset.height = .points(height) }
        else { preset.height = .percent(100) }
        if let x { preset.x = .points(x) } else { preset.x = .right }
        if let y { preset.y = .points(y) } else { preset.y = .bottom }
        return preset
    }

    func preset(named name: String) -> FramePreset? {
        if let p = frames?[name] { return p }
        if name == "default" { return legacyDefaultPreset() }
        return nil
    }

    func resolveFrame(preset name: String, on screen: NSScreen) -> NSRect? {
        guard let preset = preset(named: name) else { return nil }
        return FrameResolver.computedRect(preset, on: screen, fallbackWidth: CGFloat(width))
    }

    func initialFrame(on screen: NSScreen) -> NSRect {
        let name = launchPresetName(screenCount: NSScreen.screens.count)
        if let rect = resolveFrame(preset: name, on: screen) { return rect }
        return FrameResolver.computedRect(legacyDefaultPreset(), on: screen, fallbackWidth: CGFloat(width))
    }

    /// Sites from `sitesCommand` output. Extra keys per entry are ignored; nil when the output is
    /// not a JSON array or holds no valid entries, so the caller keeps the static `sites`.
    static func parseSites(_ data: Data) -> [SiteConfig]? {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return nil }
        let sites = raw.compactMap { item -> SiteConfig? in
            guard let entry = try? JSONSerialization.data(withJSONObject: item) else { return nil }
            return try? JSONDecoder().decode(SiteConfig.self, from: entry)
        }
        return sites.isEmpty ? nil : sites
    }

    /// Runs `sitesCommand` through /bin/zsh and parses its stdout. Blocking — call off the main thread.
    /// GUI apps get launchd's bare PATH, so Homebrew and sbin (md5 etc.) are prepended.
    static func runSitesCommand(_ command: String, timeout: TimeInterval = 15) -> [SiteConfig]? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-c", command]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
        proc.environment = env
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice
        proc.standardInput = FileHandle.nullDevice
        do { try proc.run() } catch { return nil }

        // Read on another thread: a grandchild (pipeline, background job) can hold the pipe
        // open after zsh exits or is killed, and readDataToEndOfFile would block forever.
        var data = Data()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            data = out.fileHandleForReading.readDataToEndOfFile()
            done.signal()
        }
        guard done.wait(timeout: .now() + timeout) == .success else {
            if proc.isRunning { proc.terminate() }
            return nil
        }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        return parseSites(data)
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

private let hotkeyKeyCodes: [String: UInt16] = [
    "a":0,"b":11,"c":8,"d":2,"e":14,"f":3,"g":5,"h":4,"i":34,"j":38,
    "k":40,"l":37,"m":46,"n":45,"o":31,"p":35,"q":12,"r":15,"s":1,
    "t":17,"u":32,"v":9,"w":13,"x":7,"y":16,"z":6,
    "0":29,"1":18,"2":19,"3":20,"4":21,"5":23,"6":22,"7":26,"8":28,"9":25,
    "\\":42,"/":44,"]":30,"[":33,"-":27,"=":24,"`":50,";":41,"'":39,
    ",":43,".":47,"space":49,"return":36,"tab":48,"delete":51,
    "left":123,"right":124,"up":126,"down":125,
    "f1":122,"f2":120,"f3":99,"f4":118,"f5":96,"f6":97,"f7":98,
    "f8":100,"f9":101,"f10":109,"f11":103,"f12":111,
]

// Physical key code + exact modifier set, so a chord matches on any keyboard layout.
func parseHotkey(_ str: String?) -> (keyCode: UInt16, mods: NSEvent.ModifierFlags)? {
    guard let str else { return nil }
    let parts = str.lowercased().components(separatedBy: "+")
    guard let keyPart = parts.last, let keyCode = hotkeyKeyCodes[keyPart] else { return nil }
    var mods: NSEvent.ModifierFlags = []
    for mod in parts.dropLast() {
        switch mod {
        case "cmd", "command":  mods.insert(.command)
        case "shift":           mods.insert(.shift)
        case "option", "alt":   mods.insert(.option)
        case "ctrl", "control": mods.insert(.control)
        default: return nil
        }
    }
    // A bare key would swallow ordinary typing in the web view.
    return mods.isEmpty ? nil : (keyCode, mods)
}

func hotkeyMatches(_ spec: String?, _ event: NSEvent) -> Bool {
    guard let hk = parseHotkey(spec) else { return false }
    return event.keyCode == hk.keyCode
        && event.modifierFlags.intersection([.command, .shift, .option, .control]) == hk.mods
}
