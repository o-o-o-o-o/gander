import AppKit
import Carbon
import ServiceManagement
import WebKit

class AppDelegate: NSObject, NSApplicationDelegate {
    let config: AppConfig
    var panel: SidebarPanel?
    var statusItem: NSStatusItem?

    // Carbon hotkey refs — kept alive for the app lifetime
    private var toggleHotkey: EventHotKeyRef?
    private var sitesHotkey:  EventHotKeyRef?
    private var nextHotkey:   EventHotKeyRef?
    private var prevHotkey:   EventHotKeyRef?
    private var carbonHandler: EventHandlerRef?

    init(config: AppConfig) {
        self.config = config
    }

    // Two overloads: IPC notifications carry userInfo dicts; URL scheme carries URLComponents.
    // Both extract the same four optional doubles — kept separate to avoid a bridging layer.
    private func frameConfig(from userInfo: [AnyHashable: Any]?) -> FrameConfig {
        func read(_ key: String) -> Double? {
            guard let raw = userInfo?[key] else { return nil }
            if let number = raw as? NSNumber { return number.doubleValue }
            if let text = raw as? String { return Double(text) }
            return nil
        }

        return FrameConfig(x: read("x"),
                           y: read("y"),
                           width: read("width"),
                           height: read("height"))
    }

    private func frameConfig(from components: URLComponents?) -> FrameConfig {
        func read(_ key: String) -> Double? {
            components?.queryItems?.first(where: { $0.name == key }).flatMap { item in
                item.value.flatMap(Double.init)
            }
        }

        return FrameConfig(x: read("x"),
                           y: read("y"),
                           width: read("width"),
                           height: read("height"))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupEditMenu()
        panel = SidebarPanel(config: config)
        if !UserDefaults.standard.bool(forKey: "hideMenuBarIcon.\(config.name)") {
            setupMenuBar()
        }
        setupGlobalHotkeys()
        setupIPC()
        setupURLScheme()
    }

    /// Standard Edit menu — never shown (accessory app) but required so ⌘C/⌘V route to the
    /// first responder. The panel's local key monitor handles the non-activating-panel case.
    private func setupEditMenu() {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let item = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        item.submenu = edit
        let main = NSMenu()
        main.addItem(item)
        NSApp.mainMenu = main
    }

    // MARK: Menu bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: 30)
        let btn = statusItem!.button!
        btn.image = gooseMenubarIcon()
        btn.contentTintColor = nil
        btn.action = #selector(togglePanel)
        btn.target = self

        let menu = NSMenu()
        menu.delegate = self
        let title = config.name == "default" ? "Gander" : "Gander — \(config.name)"

        func item(_ t: String, _ sel: Selector, tag: Int = 0) -> NSMenuItem {
            let i = NSMenuItem(title: t, action: sel, keyEquivalent: "")
            i.target = self
            i.tag = tag
            return i
        }

        menu.addItem(item("\(title)  ⌘⇧\\", #selector(togglePanel)))
        menu.addItem(item("Sites…  ⌘⇧/",    #selector(openSitePicker)))
        menu.addItem(.separator())
        menu.addItem(item("Open at Login",        #selector(toggleLaunchAtLogin),      tag: 101))
        menu.addItem(item("Hide Menu Bar Icon…",  #selector(confirmHideMenuBarIcon)))
        menu.addItem(.separator())
        menu.addItem(item("Help", #selector(showHelp)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc func togglePanel()    { panel?.toggle() }
    @objc func openSitePicker() { panel?.toggleSitePicker() }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not update Login Item"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func confirmHideMenuBarIcon() {
        let hotkey = prettyHotkey(config.hotkeys.toggle)
        let alert = NSAlert()
        alert.messageText = "Hide Menu Bar Icon?"
        alert.informativeText = """
            The Gander icon will be removed from the menu bar.

            You can still use \(hotkey) to show or hide the sidebar. To restore the icon at any time, run:
                gander menubar
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Hide Icon")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        UserDefaults.standard.set(true, forKey: "hideMenuBarIcon.\(config.name)")
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func restoreMenuBarIcon() {
        UserDefaults.standard.set(false, forKey: "hideMenuBarIcon.\(config.name)")
        if statusItem == nil { setupMenuBar() }
    }

    private func prettyHotkey(_ spec: String?) -> String {
        guard let spec else { return "your keyboard shortcut" }
        var s = spec
        for (word, sym) in [("command","⌘"),("cmd","⌘"),("shift","⇧"),("option","⌥"),("alt","⌥"),("ctrl","⌃"),("control","⌃")] {
            s = s.replacingOccurrences(of: word, with: sym, options: .caseInsensitive)
        }
        return s.replacingOccurrences(of: "+", with: "")
    }

    private var helpPanel: NSPanel?

    @objc func showHelp() {
        if let existing = helpPanel, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let name = config.name
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 680),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        panel.title = name == "default" ? "Gander Help" : "Gander Help — \(name)"
        panel.isReleasedWhenClosed = false
        panel.center()

        let wv = WKWebView(frame: panel.contentView!.bounds)
        wv.autoresizingMask = [.width, .height]
        wv.loadHTMLString(HelpContent.html(
            name: name,
            toggleKey: prettyHotkey(config.hotkeys.toggle),
            sitesKey:  prettyHotkey(config.hotkeys.sites),
            nextKey:   prettyHotkey(config.hotkeys.next),
            prevKey:   prettyHotkey(config.hotkeys.prev)
        ), baseURL: Bundle.main.resourceURL)
        panel.contentView!.addSubview(wv)
        helpPanel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func gooseMenubarIcon() -> NSImage {
        // Load greg.png from bundle (white already removed at build time → template-ready)
        if let url = Bundle.main.url(forResource: "greg", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            // Render slightly smaller than the status item bounds so it sits with other menu bar icons.
            img.size = NSSize(width: 16, height: 16)
            img.isTemplate = true
            return img
        }
        // Fallback when running outside .app bundle during development
        let size: CGFloat = 18
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15)]
        NSAttributedString(string: "🪿", attributes: attrs)
            .draw(at: .init(x: 1, y: 1))
        img.unlockFocus()
        return img
    }

    // MARK: Global hotkeys via Carbon RegisterEventHotKey
    // No Input Monitoring permission needed — works system-wide immediately.
    // Hotkeys are configured in the JSON config file under the "hotkeys" key.

    private func setupGlobalHotkeys() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let userData else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(event, UInt32(kEventParamDirectObject), UInt32(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let me = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                switch hkID.id {
                case 1: me.panel?.toggle()
                case 2: me.panel?.toggleSitePicker()
                case 3: me.panel?.nextSite()
                case 4: me.panel?.prevSite()
                default: break
                }
            }
            return noErr
        }, 1, &spec, selfPtr, &carbonHandler)

        let sig = OSType(0x47414E44) // 'GAND'
        registerHotkey(config.hotkeys.toggle, id: 1, sig: sig, ref: &toggleHotkey)
        registerHotkey(config.hotkeys.sites,  id: 2, sig: sig, ref: &sitesHotkey)
        registerHotkey(config.hotkeys.next,   id: 3, sig: sig, ref: &nextHotkey)
        registerHotkey(config.hotkeys.prev,   id: 4, sig: sig, ref: &prevHotkey)
    }

    private func registerHotkey(_ spec: String?, id: UInt32, sig: OSType, ref: inout EventHotKeyRef?) {
        guard let spec, let (keyCode, mods) = parseHotkey(spec) else { return }
        let hkID = EventHotKeyID(signature: sig, id: id)
        RegisterEventHotKey(keyCode, mods, hkID, GetApplicationEventTarget(), 0, &ref)
    }

    private func parseHotkey(_ str: String) -> (keyCode: UInt32, mods: UInt32)? {
        let parts = str.lowercased().components(separatedBy: "+")
        guard let keyPart = parts.last, !keyPart.isEmpty else { return nil }
        var mods: UInt32 = 0
        for mod in parts.dropLast() {
            switch mod {
            case "cmd", "command": mods |= UInt32(cmdKey)
            case "shift":          mods |= UInt32(shiftKey)
            case "option", "alt":  mods |= UInt32(optionKey)
            case "ctrl", "control": mods |= UInt32(controlKey)
            default: break
            }
        }
        let keyCodes: [String: UInt32] = [
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
        guard let keyCode = keyCodes[keyPart] else { return nil }
        return (keyCode, mods)
    }

    // MARK: IPC — NSDistributedNotificationCenter
    //
    // Notification names are scoped to the instance name so multiple instances coexist.
    // CLI:         gander [name] toggle / show / hide / open <url> / sites
    // AppleScript: do shell script "gander work open https://example.com"

    private func setupIPC() {
        let nc = DistributedNotificationCenter.default()
        nc.addObserver(self, selector: #selector(ipcToggle),    name: config.notifToggle,   object: nil)
        nc.addObserver(self, selector: #selector(ipcShow(_:)),  name: config.notifShow,     object: nil)
        nc.addObserver(self, selector: #selector(ipcHide),      name: config.notifHide,     object: nil)
        nc.addObserver(self, selector: #selector(ipcOpen(_:)),  name: config.notifOpen,     object: nil)
        nc.addObserver(self, selector: #selector(ipcFrame(_:)), name: config.notifFrame,    object: nil)
        nc.addObserver(self, selector: #selector(ipcSites),     name: config.notifSites,    object: nil)
        nc.addObserver(self, selector: #selector(ipcNext),      name: config.notifNext,     object: nil)
        nc.addObserver(self, selector: #selector(ipcPrev),      name: config.notifPrev,     object: nil)
        nc.addObserver(self, selector: #selector(ipcMenuBar),   name: config.notifMenuBar,  object: nil)
    }

    @objc private func ipcToggle()                { panel?.toggle() }
    @objc private func ipcShow(_ n: Notification) {
        panel?.applyFrame(frameConfig(from: n.userInfo))
        panel?.show()
    }
    @objc private func ipcHide()                  { panel?.hide() }
    @objc private func ipcSites()                 { panel?.toggleSitePicker() }
    @objc private func ipcNext()                  { panel?.nextSite() }
    @objc private func ipcPrev()                  { panel?.prevSite() }
    @objc private func ipcOpen(_ n: Notification) {
        guard let url = n.userInfo?["url"] as? String else { return }
        if let raw = n.userInfo?["shortcut"] {
            let n = (raw as? Int) ?? (raw as? NSNumber).map { $0.intValue } ?? Int(String(describing: raw))
            if let n, (1...9).contains(n) { panel?.setTransientShortcut(n, url: url) }
        }
        panel?.applyFrame(frameConfig(from: n.userInfo))
        panel?.show()
        panel?.load(url)
    }
    @objc private func ipcFrame(_ n: Notification) {
        panel?.applyFrame(frameConfig(from: n.userInfo))
    }
    @objc private func ipcMenuBar() { restoreMenuBarIcon() }

    // MARK: URL scheme  gander://
    //
    //   gander://toggle  /  gander://work/toggle
    //   gander://open?url=https%3A%2F%2Fexample.com&width=480&height=900
    //   gander://frame?x=100&y=80&width=420&height=1000
    //   gander://sites
    //
    // Shell:       open -g "gander://toggle"
    // AppleScript: open location "gander://toggle"

    private func setupURLScheme() {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleURL(_ event: NSAppleEventDescriptor, withReplyEvent: NSAppleEventDescriptor) {
        guard let raw   = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url   = URL(string: raw),
              url.scheme == "gander" else { return }

        let parts  = url.pathComponents.filter { $0 != "/" }
        let target = parts.count > 1 ? parts[0] : (url.host ?? "default")
        let action = parts.count > 1 ? parts[1] : (parts.first ?? url.host ?? "toggle")

        guard target == config.name || (target == "default" && config.name == "default") else { return }

        switch action {
        case "toggle": panel?.toggle()
        case "show":
            panel?.applyFrame(frameConfig(from: URLComponents(url: url, resolvingAgainstBaseURL: false)))
            panel?.show()
        case "hide":   panel?.hide()
        case "sites":  panel?.toggleSitePicker()
        case "open":
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let dest = comps?.queryItems?.first(where: { $0.name == "url" })?.value {
                if let sStr = comps?.queryItems?.first(where: { $0.name == "shortcut" })?.value,
                   let n = Int(sStr), (1...9).contains(n) {
                    panel?.setTransientShortcut(n, url: dest)
                }
                panel?.applyFrame(frameConfig(from: comps))
                panel?.show()
                panel?.load(dest)
            }
        case "frame":
            panel?.applyFrame(frameConfig(from: URLComponents(url: url, resolvingAgainstBaseURL: false)))
        default: break
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        if let item = menu.item(withTag: 101) {
            item.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }
}
