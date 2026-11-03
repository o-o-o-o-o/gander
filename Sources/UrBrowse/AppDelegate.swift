import AppKit
import ServiceManagement
import UrBrowseSpec
import UrKit
import WebKit

class AppDelegate: NSObject, NSApplicationDelegate {
    let config: AppConfig
    let pot: Pot
    var panel: SidebarPanel?
    var statusItem: NSStatusItem?
    private var ipc: IPCServer?

    private var lastScreenCount: Int = 0
    private var layoutDebounce: DispatchWorkItem?

    init(config: AppConfig, pot: Pot) {
        self.config = config
        self.pot = pot
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Claim the pot's socket first: if this pot is already running, step aside instead of
        // opening a second panel (the old "two default instances" LaunchAgent problem).
        let server = IPCServer(socketURL: pot.socketURL) { [weak self] request, reply in
            guard let self else { reply(.failure("shutting down")); return }
            self.handle(request, reply: reply)
        }
        do {
            try server.start()
        } catch {
            fputs("Ur Browse: \(error) — not starting a second copy of pot '\(pot.name)'\n", stderr)
            exit(0)
        }
        ipc = server

        setupEditMenu()
        panel = SidebarPanel(config: config, pot: pot)
        if !UserDefaults.standard.bool(forKey: "hideMenuBarIcon.\(config.name)") {
            setupMenuBar()
        }
        setupURLScheme()
        setupFrameAuto()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ipc?.stop()
    }

    private func setupFrameAuto() {
        guard config.frameAuto != nil else { return }
        lastScreenCount = NSScreen.screens.count
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screenParametersChanged() {
        layoutDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.handleDisplayLayoutChange() }
        layoutDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    private func handleDisplayLayoutChange() {
        guard config.frameAuto != nil, let panel else { return }
        let count = NSScreen.screens.count
        let countChanged = count != lastScreenCount
        lastScreenCount = count

        if countChanged || config.frameAuto?.onLayoutChange == true {
            panel.applyAutoFrameForCurrentDisplays()
        }
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
        let title = config.name == "default" ? "Ur Browse" : "Ur Browse — \(config.name)"

        func item(_ t: String, _ sel: Selector, tag: Int = 0) -> NSMenuItem {
            let i = NSMenuItem(title: t, action: sel, keyEquivalent: "")
            i.target = self
            i.tag = tag
            return i
        }

        menu.addItem(item("\(title)  ⌘⇧\\", #selector(togglePanel)))
        menu.addItem(item("Sites…  ⌘⇧/",    #selector(openSitePicker)))
        menu.addItem(.separator())
        menu.addItem(item("Reload Slip Scripts", #selector(reloadSlipFromMenu)))
        menu.addItem(item("Show Pot Folder",     #selector(showPotFolder)))
        menu.addItem(.separator())
        // SMAppService.mainApp launches the bundle without arguments, i.e. only the default pot.
        // Other pots: `ur-browse <pot> start --login` (a per-pot LaunchAgent).
        if pot.name == Pot.defaultName {
            menu.addItem(item("Open at Login",    #selector(toggleLaunchAtLogin),      tag: 101))
        }
        menu.addItem(item("Hide Menu Bar Icon…",  #selector(confirmHideMenuBarIcon)))
        menu.addItem(.separator())
        menu.addItem(item("Help", #selector(showHelp)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc func togglePanel()    { panel?.toggle() }
    @objc func openSitePicker() { panel?.toggleSitePicker() }
    @objc private func reloadSlipFromMenu() { panel?.reloadSlip() }

    @objc private func showPotFolder() {
        try? FileManager.default.createDirectory(at: pot.slipDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([pot.slipDirectory])
    }

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
            The Ur Browse icon will be removed from the menu bar.

            You can still use \(hotkey) to show or hide the sidebar. To restore the icon at any time, run:
                ur-browse menubar
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
        panel.title = name == "default" ? "Ur Browse Help" : "Ur Browse Help — \(name)"
        panel.isReleasedWhenClosed = false
        panel.center()

        let wv = WKWebView(frame: panel.contentView!.bounds)
        wv.autoresizingMask = [.width, .height]
        wv.enableInspection()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        wv.loadHTMLString(HelpContent.html(
            name: name,
            version: version,
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

    // MARK: Commands — one dispatcher for every surface
    //
    // CLI (`ur-browse work open …`) and other pots arrive over the pot's Unix socket;
    // `ur-browse://` / `gander://` URLs arrive as Apple Events. Both become a UrKit `Request`,
    // then a typed `BrowseCommand`, then run here.

    private func handle(_ request: Request, reply: @escaping (Response) -> Void) {
        do {
            reply(execute(try BrowseCommand(request), request: request))
        } catch {
            reply(.failure("\(error)"))
        }
    }

    private func execute(_ command: BrowseCommand, request: Request) -> Response {
        guard let panel else { return .failure("pot '\(pot.name)' is still starting") }
        switch command {
        case .toggle:
            panel.toggle()
        case .show(let frame):
            panel.applyFrame(frame)
            panel.show()
        case .hide:
            panel.hide()
        case .picker:
            panel.toggleSitePicker()
        case .next:
            panel.nextSite()
        case .prev:
            panel.prevSite()
        case .open(let url, let shortcut, let frame):
            if let shortcut { panel.setTransientShortcut(shortcut, url: url) }
            panel.applyFrame(frame)
            panel.show()
            panel.load(url)
        case .site(let id, let path, let frame):
            do {
                let site = try panel.openSite(id: id, path: path)
                panel.applyFrame(frame)
                panel.show()
                return .success(panel.currentInfo(), text: "\(site.name)")
            } catch {
                return .failure("\(error)")
            }
        case .listSites:
            let sites = panel.siteListing()
            let width = sites.map(\.id.count).max() ?? 0
            let text = sites.map { s in
                let marker = s.active ? "▸" : (s.open ? "•" : " ")
                let key = s.shortcut.map { " ⌘\($0)" } ?? ""
                let temp = s.temporary ? " (temporary)" : ""
                return "\(marker) \(s.id.padding(toLength: width, withPad: " ", startingAt: 0))  \(s.name)  \(s.url)\(key)\(temp)"
            }.joined(separator: "\n")
            return .success(sites, text: text)
        case .current:
            let info = panel.currentInfo()
            return .success(info, text: [info.title, info.url].compactMap { $0 }.joined(separator: "\n"))
        case .frame(let frame):
            panel.applyFrame(frame)
        case .menubar:
            restoreMenuBarIcon()
        case .reloadSlip:
            panel.reloadSlip()
            let names = panel.slipScripts.map(\.file)
            return .success(names, text: names.isEmpty
                ? "no slip scripts in \(pot.slipDirectory.path)"
                : "reloaded \(names.count) slip script(s): \(names.joined(separator: ", "))")
        case .listSlip:
            let infos = panel.slipScripts.map(\.info)
            let text = infos.isEmpty
                ? "no slip scripts in \(pot.slipDirectory.path)"
                : infos.map { "\($0.file)  \($0.matches.isEmpty ? "all pages" : $0.matches.joined(separator: " "))" }
                    .joined(separator: "\n")
            return .success(infos, text: text)
        case .info:
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
            let info = PotInfo(pot: pot.name, app: BrowseSpec.spec.app, version: version, glaze: config.glaze,
                               visible: panel.isVisible, sites: panel.siteListing().count,
                               slip: panel.slipScripts.map(\.file), config: pot.configURL.path)
            return .success(info)
        case .quit:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { NSApp.terminate(nil) }
        }
        return .success()
    }

    // MARK: URL scheme  ur-browse://  (and legacy gander://)
    //
    //   ur-browse://toggle                 ur-browse://work/toggle
    //   ur-browse://work/site/gh/o-o-o-o-o/ur-browse
    //   ur-browse://open?url=https%3A%2F%2Fexample.com&width=480&height=900
    //   ur-browse://frame?x=100&y=80&width=420&height=1000
    //
    // Shell:       open -g "ur-browse://work/site/gh"
    // AppleScript: open location "ur-browse://toggle"
    //
    // All pots share one bundle, so LaunchServices hands a URL to whichever process it picks.
    // A URL for another pot is forwarded to that pot's socket rather than dropped.

    private func setupURLScheme() {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleURL(_ event: NSAppleEventDescriptor, withReplyEvent: NSAppleEventDescriptor) {
        let spec = BrowseSpec.spec
        guard let raw = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: raw),
              let request = RequestParser.parse(url: url, schemes: spec.schemes, verbs: spec.verbs,
                                                defaultVerb: spec.defaultVerb) else { return }
        if request.pot == pot.name {
            handle(request) { response in
                if !response.ok { fputs("Ur Browse: \(raw): \(response.error ?? "failed")\n", stderr) }
            }
            return
        }
        let target = spec.pot(request.pot)
        let autostart = spec.autostartVerbs.contains(request.verb)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if !target.isRunning {
                guard autostart, let self else {
                    fputs("Ur Browse: pot '\(target.name)' is not running (\(raw))\n", stderr)
                    return
                }
                self.launchPot(target)
                let deadline = Date().addingTimeInterval(8)
                while !target.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
            }
            do {
                let response = try IPCClient.send(request, to: target.socketURL)
                if !response.ok { fputs("Ur Browse: \(raw): \(response.error ?? "failed")\n", stderr) }
            } catch {
                fputs("Ur Browse: pot '\(target.name)' did not answer (\(raw)): \(error)\n", stderr)
            }
        }
    }

    /// Starts another pot as a separate process of this same app (or dev binary).
    private func launchPot(_ target: Pot) {
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app" else {
            // Dev build (.build/release/UrBrowseApp): run the binary directly.
            guard let exe = Bundle.main.executableURL else { return }
            let proc = Process()
            proc.executableURL = exe
            proc.arguments = ["--pot", target.name]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
            return
        }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.createsNewApplicationInstance = true   // a new process even though this one is running
        cfg.activates = false
        cfg.arguments = ["--pot", target.name]
        NSWorkspace.shared.openApplication(at: bundle, configuration: cfg) { _, error in
            if let error { fputs("Ur Browse: could not start pot '\(target.name)': \(error)\n", stderr) }
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
