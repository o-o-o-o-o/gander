import AppKit
import WebKit

private let PICKER_HEIGHT: CGFloat = 260

class SidebarPanel: NSPanel, NSToolbarDelegate {
    private let config: AppConfig
    private var transientSites: [SiteConfig] = []
    private var transientShortcuts: [Int: String] = [:]  // runtime-only; set via URL scheme shortcut param

    // One persistent WKWebView per canonical URL — sessions (cookies, JS state, scroll) survive
    // site switches. Switching just swaps which WKWebView is in the view hierarchy.
    // Tradeoff: each WKWebView spawns a Web Content process; fine for 5–10 sites.
    private var sessions:  [String: WKWebView] = [:]   // keyed by canonicalURLString(site.url)
    private var activeKey: String? = nil

    private var webContainer:            NSView!
    private var pickerView:              SitePickerView!
    private var pickerHeightConstraint:  NSLayoutConstraint!
    private var pickerVisible = false

    // Site cycling
    private var activeSiteIndex: Int = 0

    private var titleObservation: NSKeyValueObservation?

    init(config: AppConfig) {
        self.config = config

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let rect = config.initialFrame(on: screen)

        let mask: NSWindow.StyleMask = config.chrome
            ? [.titled, .closable, .resizable, .nonactivatingPanel]
            : [.resizable, .nonactivatingPanel]

        super.init(contentRect: rect, styleMask: mask, backing: .buffered, defer: false)

        collectionBehavior    = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        level                 = .floating
        isFloatingPanel       = true
        hidesOnDeactivate     = false
        isReleasedWhenClosed  = false

        if config.chrome { setupToolbar() }

        setupLayout()  // must come after toolbar so contentView top is below toolbar

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let cmd    = event.modifierFlags.contains(.command)
            let shift  = event.modifierFlags.contains(.shift)
            let noExtra = event.modifierFlags.intersection([.option, .control]).isEmpty
            let ch = event.charactersIgnoringModifiers
            if cmd && !shift && noExtra && ch == "r" { self.activeWebView?.reload(); return nil }
            if cmd &&  shift && noExtra && ch == "o" { self.openInExternalBrowser(); return nil }
            if cmd && !shift && noExtra, let ch, ch.count == 1, let n = Int(ch), (1...9).contains(n),
               self.config.pinned != nil || !self.transientShortcuts.isEmpty {
                self.activateShortcut(n); return nil
            }
            // Non-activating panel: active app's menu bar still owns ⌘C/⌘V unless we intercept.
            if cmd && !shift && noExtra && self.isKeyWindow, let ch {
                let edit: Selector? = switch ch {
                case "c": #selector(NSText.copy(_:))
                case "v": #selector(NSText.paste(_:))
                case "x": #selector(NSText.cut(_:))
                case "a": #selector(NSText.selectAll(_:))
                default: nil
                }
                if let edit, NSApp.sendAction(edit, to: nil, from: event) { return nil }
            }
            return event
        }

        // Open first site on launch
        if let first = config.sites.first {
            switchToSite(first, animated: false)
        } else {
            openURL(config.defaultUrl, animated: false)
        }
    }

    private var availableSites: [SiteConfig] {
        config.sites + transientSites
    }

    // Returns sites keyed by shortcut number based on the pinned mode.
    // "auto"   → first 9 config sites get ⌘1–⌘9 in order
    // "manual" → sites with a shortcut field; first occurrence wins on duplicates
    private var configShortcuts: [Int: SiteConfig] {
        switch config.pinned {
        case "auto":
            return Dictionary(uniqueKeysWithValues:
                config.sites.prefix(9).enumerated().map { ($0.offset + 1, $0.element) })
        case "manual":
            var result: [Int: SiteConfig] = [:]
            for site in config.sites where site.shortcut != nil {
                let n = site.shortcut!
                if result[n] == nil { result[n] = site }  // first wins
            }
            return result
        default:
            return [:]
        }
    }

    // Merged map of url → shortcut number for the picker; transient overrides config.
    private func shortcutURLMap() -> [String: Int] {
        var result: [String: Int] = [:]
        for (n, site) in configShortcuts { result[site.url] = n }
        for (n, url) in transientShortcuts { result[url] = n }
        return result
    }

    private func refreshPickerSites() {
        pickerView.configure(sites: availableSites, shortcuts: shortcutURLMap())
    }

    func setTransientShortcut(_ n: Int, url: String) {
        guard (1...9).contains(n) else { return }
        transientShortcuts[n] = url
        _ = siteForOpening(urlString: url)  // creates transient site entry + session if not already in list
        refreshPickerSites()                // update shortcut badges
    }

    private func activateShortcut(_ n: Int) {
        if let url = transientShortcuts[n] {
            // switchToSite restores the existing session; siteForOpening creates one if needed
            switchToSite(siteForOpening(urlString: url))
        } else if let site = configShortcuts[n] {
            switchToSite(site)
        }
    }

    private func siteKey(for urlString: String) -> String {
        canonicalURLString(urlString)
    }

    private func site(namedByURL urlString: String) -> SiteConfig? {
        let key = siteKey(for: urlString)
        return availableSites.first { siteKey(for: $0.url) == key }
    }

    private func temporarySiteName(for urlString: String) -> String {
        if let host = URL(string: urlString)?.host, !host.isEmpty {
            return host
        }
        return urlString
    }

    private func siteForOpening(urlString: String) -> SiteConfig {
        if let existing = site(namedByURL: urlString) {
            return existing
        }

        let temporary = SiteConfig(name: temporarySiteName(for: urlString),
                                   url: urlString,
                                   temporary: true)
        transientSites.append(temporary)
        refreshPickerSites()
        return temporary
    }

    // MARK: Layout

    private func setupLayout() {
        webContainer = NSView()
        webContainer.translatesAutoresizingMaskIntoConstraints = false

        pickerView = SitePickerView(frame: .zero)
        refreshPickerSites()
        pickerView.translatesAutoresizingMaskIntoConstraints = false
        pickerView.onSelect  = { [weak self] url in self?.pickerDidSelect(url: url) }
        pickerView.onDismiss = { [weak self] in self?.hideSitePicker() }

        contentView!.addSubview(pickerView)
        contentView!.addSubview(webContainer)

        pickerHeightConstraint = pickerView.heightAnchor.constraint(equalToConstant: 0)

        // Color stripe at top of content — works in both chrome and no-chrome modes,
        // avoids NSTitlebarAccessoryViewController which conflicts with toolbar layout
        if let color = config.accentColor, config.stripeHeight > 0 {
            let stripe = NSView()
            stripe.wantsLayer = true
            stripe.layer?.backgroundColor = color.cgColor
            stripe.translatesAutoresizingMaskIntoConstraints = false
            contentView!.addSubview(stripe)
            NSLayoutConstraint.activate([
                stripe.topAnchor.constraint(equalTo: contentView!.topAnchor),
                stripe.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor),
                stripe.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor),
                stripe.heightAnchor.constraint(equalToConstant: CGFloat(config.stripeHeight)),
                pickerView.topAnchor.constraint(equalTo: stripe.bottomAnchor),
            ])
        } else {
            pickerView.topAnchor.constraint(equalTo: contentView!.topAnchor).isActive = true
        }

        NSLayoutConstraint.activate([
            pickerView.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor),
            pickerView.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor),
            pickerHeightConstraint,

            webContainer.topAnchor.constraint(equalTo: pickerView.bottomAnchor),
            webContainer.bottomAnchor.constraint(equalTo: contentView!.bottomAnchor),
            webContainer.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor),
            webContainer.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor),
        ])
    }

    // MARK: Session management

    private func makeWebView() -> WKWebView {
        let wv = WKWebView(frame: .zero)
        wv.translatesAutoresizingMaskIntoConstraints = false
        return wv
    }

    private func pinToContainer(_ wv: WKWebView) {
        webContainer.addSubview(wv)
        NSLayoutConstraint.activate([
            wv.topAnchor.constraint(equalTo: webContainer.topAnchor),
            wv.bottomAnchor.constraint(equalTo: webContainer.bottomAnchor),
            wv.leadingAnchor.constraint(equalTo: webContainer.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: webContainer.trailingAnchor),
        ])
    }

    // Switch to a named site from the config — creates session on first visit
    func switchToSite(_ site: SiteConfig, animated: Bool = true) {
        if let idx = availableSites.firstIndex(where: { siteKey(for: $0.url) == siteKey(for: site.url) }) {
            activeSiteIndex = idx
        }
        let key = siteKey(for: site.url)
        let wv: WKWebView
        if let existing = sessions[key] {
            wv = existing
        } else {
            wv = makeWebView()
            sessions[key] = wv
            if let url = URL(string: site.url) {
                wv.load(URLRequest(url: url))
            }
        }
        activateWebView(wv, key: key, animated: animated)
    }

    // Load an arbitrary URL into the current session (used by IPC/URL scheme `open`)
    func switchToURL(_ urlString: String, animated: Bool = true) {
        let key = siteKey(for: urlString)
        let wv: WKWebView
        if let existing = sessions[key] {
            wv = existing
        } else {
            wv = makeWebView()
            sessions[key] = wv
            if let url = URL(string: urlString) { wv.load(URLRequest(url: url)) }
        }
        activateWebView(wv, key: key, animated: animated)
    }

    func openURL(_ urlString: String, animated: Bool = true) {
        let site = siteForOpening(urlString: urlString)
        switchToSite(site, animated: animated)
    }

    func applyFrame(_ frame: FrameConfig) {
        guard !frame.isEmpty else { return }
        let visible = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? frameRect(forContentRect: self.frame)
        var next = self.frame

        if let width = frame.width {
            next.size.width = CGFloat(width)
        }
        if let height = frame.height {
            next.size.height = CGFloat(height)
        }
        if let x = frame.x {
            next.origin.x = CGFloat(x)
        }
        if let y = frame.y {
            next.origin.y = CGFloat(y)
        }

        next.size.width = min(max(next.size.width, 240), visible.width)
        next.size.height = min(max(next.size.height, 240), visible.height)
        next.origin.x = min(max(next.origin.x, visible.minX), visible.maxX - next.size.width)
        next.origin.y = min(max(next.origin.y, visible.minY), visible.maxY - next.size.height)

        setFrame(next, display: true, animate: false)
    }

    private func activateWebView(_ wv: WKWebView, key: String, animated: Bool) {
        guard key != activeKey else { return }
        if let old = activeKey.flatMap({ sessions[$0] }) {
            old.removeFromSuperview()
        }
        activeKey = key
        pinToContainer(wv)

        titleObservation = wv.observe(\.title, options: [.initial, .new]) { [weak self] webView, _ in
            guard let self, self.config.chrome else { return }
            let fallback = self.config.name == "default" ? "Sidebar" : self.config.name
            DispatchQueue.main.async {
                self.title = webView.title?.isEmpty == false ? webView.title! : fallback
            }
        }
    }

    var activeWebView: WKWebView? {
        activeKey.flatMap { sessions[$0] }
    }

    // MARK: Site cycling (⌘⇧] / ⌘⇧[)

    func nextSite() {
        guard !availableSites.isEmpty else { return }
        activeSiteIndex = (activeSiteIndex + 1) % availableSites.count
        switchToSite(availableSites[activeSiteIndex])
    }

    func prevSite() {
        guard !availableSites.isEmpty else { return }
        activeSiteIndex = (activeSiteIndex - 1 + availableSites.count) % availableSites.count
        switchToSite(availableSites[activeSiteIndex])
    }

    // MARK: Public API

    // Match by exact canonical URL, then fall back to host+path (ignoring query string)
    // so that search URLs like ?q=term are associated with their parent site entry.
    private func siteMatchingURL(_ urlString: String) -> SiteConfig? {
        if let exact = site(namedByURL: urlString) { return exact }
        guard let comps = URLComponents(string: urlString), let host = comps.host else { return nil }
        return availableSites.first {
            guard let sc = URLComponents(string: $0.url), let sh = sc.host else { return false }
            return sh == host && sc.path == comps.path
        }
    }

    private func openInExternalBrowser() {
        guard let url = activeWebView?.url else { return }
        let browser = config.externalBrowser
        let ws = NSWorkspace.shared
        if let appURL = ws.urlForApplication(withBundleIdentifier: browser) {
            ws.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        for dir in ["/Applications", "\(NSHomeDirectory())/Applications", "/System/Applications"] {
            let path = "\(dir)/\(browser).app"
            if FileManager.default.fileExists(atPath: path) {
                ws.open([url], withApplicationAt: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
                return
            }
        }
        ws.open(url)
    }

    func load(_ urlString: String) {
        if let matched = siteMatchingURL(urlString) {
            switchToSite(matched)
            if let url = URL(string: urlString) { activeWebView?.load(URLRequest(url: url)) }
        } else if let url = URL(string: urlString), let wv = activeWebView {
            wv.load(URLRequest(url: url))
        }
    }
    func show()   { makeKeyAndOrderFront(nil) }
    func hide()   {
        if pickerVisible {
            pickerVisible = false
            pickerHeightConstraint.constant = 0
        }
        orderOut(nil)
    }
    func toggle() { if isVisible { hide() } else { show() } }

    // MARK: Site picker

    func showSitePicker() {
        makeKeyAndOrderFront(nil)
        if pickerVisible {
            makeFirstResponder(pickerView.searchField)
            return
        }
        pickerVisible = true
        pickerView.prepare()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            pickerHeightConstraint.animator().constant = PICKER_HEIGHT
        }
        // Guard against the case where the picker is dismissed before this fires.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.pickerVisible else { return }
            self.makeFirstResponder(self.pickerView.searchField)
        }
    }

    // When the panel becomes key (possibly async, e.g. panel wasn't key when showSitePicker
    // was called), focus the search field if the picker is open.
    override func becomeKey() {
        super.becomeKey()
        if pickerVisible {
            makeFirstResponder(pickerView.searchField)
        }
    }

    func hideSitePicker() {
        guard pickerVisible else { return }
        pickerVisible = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            pickerHeightConstraint.animator().constant = 0
        }
        makeFirstResponder(activeWebView)
    }

    private func pickerDidSelect(url: String) {
        hideSitePicker()
        if let site = site(namedByURL: url) {
            switchToSite(site)
        } else {
            openURL(url)
        }
    }

    // NSPanel with .nonactivatingPanel can only become key if it has .titled or a toolbar.
    // We have neither in chrome-free mode, so we override explicitly.
    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, pickerVisible { hideSitePicker() }
        else { super.keyDown(with: event) }
    }

    // MARK: Chrome — toolbar & color stripe

    private func setupToolbar() {
        let tb = NSToolbar(identifier: "Gander-\(config.name)")
        tb.delegate = self
        tb.displayMode = .iconOnly
        tb.autosavesConfiguration = false
        toolbar = tb
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("back"), .init("forward"), .flexibleSpace, .init("sites")]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        switch id.rawValue {
        case "back":
            item.image = NSImage(systemSymbolName: "chevron.left",  accessibilityDescription: "Back")
            item.label = "Back";    item.action = #selector(goBack);           item.target = self
        case "forward":
            item.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Forward")
            item.label = "Forward"; item.action = #selector(goForward);        item.target = self
        case "sites":
            item.image = NSImage(systemSymbolName: "list.bullet",   accessibilityDescription: "Sites")
            item.label = "Sites";   item.action = #selector(toggleSitePicker); item.target = self
        default: return nil
        }
        return item
    }

    @objc private func goBack()    { activeWebView?.goBack() }
    @objc private func goForward() { activeWebView?.goForward() }
    @objc func toggleSitePicker() { pickerVisible ? hideSitePicker() : showSitePicker() }
}
