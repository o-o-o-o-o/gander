import AppKit
import WebKit
import UrKit

private let PICKER_HEIGHT: CGFloat = 260

class SidebarPanel: NSPanel, NSToolbarDelegate {
    private let config: AppConfig
    let pot: Pot
    private(set) var store: SiteStore              // sites, temporary sites, shortcuts, ids
    private var sitesReloading = false

    // One website data store and one user-content controller per pot, shared by every session:
    // the data store isolates this pot's cookies/logins from other pots (true SSBs), and the
    // shared controller lets `slip` reload user scripts for all sessions at once.
    private let dataStore: WKWebsiteDataStore
    private let contentController = WKUserContentController()
    private(set) var slipScripts: [SlipScript] = []

    // One persistent WKWebView per canonical URL — sessions (cookies, JS state, scroll) survive
    // site switches. Switching just swaps which WKWebView is in the view hierarchy.
    // Tradeoff: each WKWebView spawns a Web Content process; fine for 5–10 sites.
    private var sessions:  [String: WKWebView] = [:]   // keyed by canonicalURLString(site.url)
    private var activeKey: String? = nil

    private var webContainer:            NSView!
    private var pickerView:              SitePickerView!
    private var pickerHeightConstraint:  NSLayoutConstraint!
    private var pickerVisible = false
    private var findBar: FindBarView?

    // Site cycling
    private var activeSiteIndex: Int = 0

    private(set) var activePresetName: String?

    private var titleObservation: NSKeyValueObservation?

    // Page-load progress bar (top stripe repurposed as a fill indicator)
    private var progressBar:               NSView!
    private var progressBarWidthConstraint: NSLayoutConstraint!
    private var progressObservation:        NSKeyValueObservation?
    private var loadingObservation:         NSKeyValueObservation?
    private var progressCollapseWorkItem:   DispatchWorkItem?

    init(config: AppConfig, pot: Pot) {
        self.config = config
        self.pot = pot
        self.store = SiteStore(sites: config.sites, pinned: config.pinned)
        self.dataStore = config.ephemeral
            ? .nonPersistent()
            : WKWebsiteDataStore(forIdentifier: pot.storageIdentifier)

        let screen = NSScreen.main ?? NSScreen.screens[0]
        activePresetName = config.launchPresetName(screenCount: NSScreen.screens.count)
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
            // byApplyingModifiers([]) recovers the base key regardless of Shift, so ⌘⇧[
            // arrives as "[" not "{" — unlike charactersIgnoringModifiers, which keeps Shift.
            let ch = event.characters(byApplyingModifiers: [])
            // Config hotkeys are local: they act only while this instance's panel is key.
            if self.isKeyWindow {
                let hk = self.config.hotkeys
                if hotkeyMatches(hk.toggle, event) { self.toggle(); return nil }
                if hotkeyMatches(hk.sites,  event) { self.toggleSitePicker(); return nil }
                if hotkeyMatches(hk.next,   event) { self.nextSite(); return nil }
                if hotkeyMatches(hk.prev,   event) { self.prevSite(); return nil }
            }
            if cmd && !shift && noExtra && ch == "r" { self.activeWebView?.reload(); return nil }
            if cmd && !shift && noExtra && ch == "[" { self.activeWebView?.goBack(); return nil }
            if cmd && !shift && noExtra && ch == "]" { self.activeWebView?.goForward(); return nil }
            // Site cycling — no isKeyWindow guard, consistent with goBack/goForward above.
            // A local monitor only sees events while we're the active app, so this is already
            // scoped to "urBrowse frontmost".
            // keyCode fallback (33/30) covers layouts where "[" / "]" aren't on those keys.
            if cmd && shift && noExtra && (ch == "[" || event.keyCode == 33) { self.prevSite(); return nil }
            if cmd && shift && noExtra && (ch == "]" || event.keyCode == 30) { self.nextSite(); return nil }
            if cmd && shift && noExtra && self.isKeyWindow && ch == "o" {
                self.openInExternalBrowser(); return nil
            }
            if cmd && !shift && noExtra, let ch, ch.count == 1, let n = Int(ch) {
                if n == 0 {
                    self.openURL(self.config.defaultUrl, animated: true)
                    return nil
                }
                if (1...9).contains(n), self.store.hasShortcuts {
                    self.activateShortcut(n)
                    return nil
                }
            }
            // Non-activating panel: active app's menu bar still owns ⌘C/⌘V unless we intercept.
            if event.keyCode == 53 && self.findBar != nil { self.hideFindBar(); return nil }
            if cmd && !shift && noExtra && ch == "f" { self.showFindBar(); return nil }
            // ⌘G / ⌘⇧G
            if cmd && noExtra && ch == "g" && self.findBar != nil {
                self.doFind(self.findBar!.searchText, backwards: shift); return nil
            }
            // ⌘⇧Z redo
            if cmd && shift && noExtra && self.isKeyWindow && ch == "z" {
                NSApp.sendAction(Selector("redo:"), to: nil, from: event); return nil
            }
            if cmd && !shift && noExtra && self.isKeyWindow, let ch,
               self.handleEditShortcut(ch, event: event) { return nil }
            return event
        }

        loadSlip()
        openURL(config.defaultUrl, animated: false)
        reloadSites()
    }

    private var availableSites: [SiteConfig] { store.all }

    /// Re-runs `sitesCommand` off the main thread; on success swaps in the new list.
    /// Failure or empty output keeps the current list.
    func reloadSites() {
        guard let command = config.sitesCommand, !sitesReloading else { return }
        sitesReloading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fresh = AppConfig.runSitesCommand(command)
            DispatchQueue.main.async {
                guard let self else { return }
                self.sitesReloading = false
                guard let fresh else { return }
                self.store.replaceConfigured(fresh)
                self.refreshPickerSites()
            }
        }
    }

    private func refreshPickerSites() {
        pickerView.configure(sites: availableSites, shortcuts: store.shortcutURLMap())
    }

    func setTransientShortcut(_ n: Int, url: String) {
        store.setTransientShortcut(n, url: url)  // creates a temporary site entry if needed
        refreshPickerSites()                     // update shortcut badges
    }

    private func activateShortcut(_ n: Int) {
        let before = availableSites.count
        guard let site = store.site(forShortcut: n) else { return }
        if availableSites.count != before { refreshPickerSites() }
        switchToSite(site)
    }

    private func siteKey(for urlString: String) -> String {
        SiteStore.key(for: urlString)
    }

    private func siteForOpening(urlString: String) -> SiteConfig {
        let (site, added) = store.siteForOpening(urlString: urlString)
        if added { refreshPickerSites() }
        return site
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

        // Page-load progress bar at top of content — works in both chrome and no-chrome
        // modes, avoids NSTitlebarAccessoryViewController which conflicts with toolbar
        // layout. Width fills 0→100% with estimatedProgress, then collapses to 0 on finish;
        // see bindProgress/handleProgress.
        if let color = config.accentColor, config.stripeHeight > 0 {
            let bar = NSView()
            bar.wantsLayer = true
            bar.layer?.backgroundColor = color.cgColor
            bar.translatesAutoresizingMaskIntoConstraints = false
            contentView!.addSubview(bar)
            progressBar = bar
            let widthConstraint = bar.widthAnchor.constraint(equalToConstant: 0)
            progressBarWidthConstraint = widthConstraint
            NSLayoutConstraint.activate([
                bar.topAnchor.constraint(equalTo: contentView!.topAnchor),
                bar.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor),
                bar.heightAnchor.constraint(equalToConstant: CGFloat(config.stripeHeight)),
                widthConstraint,
                pickerView.topAnchor.constraint(equalTo: bar.bottomAnchor),
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
        let wv = BrowseWebView(frame: .zero, configuration: makeWebViewConfiguration())
        wv.translatesAutoresizingMaskIntoConstraints = false
        // Default WKWebView UA omits "Version/… Safari/…"; some login flows reject that.
        wv.customUserAgent = Self.safariUserAgent
        wv.enableInspection()
        wv.onOpenExternally = { [weak self] in self?.openInExternalBrowser() }
        wv.onCopyURL        = { [weak self] in self?.copyCurrentURL() }
        return wv
    }

    // Suppresses the page's own scrollbar track; scrolling via trackpad/keyboard is unaffected.
    // Injected at document start so it applies before first paint, in every frame (embedded
    // maps/videos included) — same injection shape libraries like driceroland/Search use for
    // page-wide CSS (their Veiling.style helper).
    private func makeWebViewConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        config.userContentController = contentController
        return config
    }

    private static let hideScrollbarsScript: WKUserScript = {
        let css = "::-webkit-scrollbar{display:none!important}html{scrollbar-width:none!important}"
        let source = "(function(){var s=document.createElement('style');s.textContent=\"\(css)\";document.documentElement.appendChild(s);})();"
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }()

    // MARK: Slip (user scripts)

    /// (Re)reads the pot's slip folder and installs the scripts into the shared content
    /// controller. Existing pages pick them up on their next load; `reloadSlip` also reloads
    /// the active page so edits show immediately.
    private func loadSlip() {
        contentController.removeAllUserScripts()
        contentController.addUserScript(Self.hideScrollbarsScript)
        slipScripts = SlipScript.load(from: pot.slipDirectory)
        for script in slipScripts {
            contentController.addUserScript(
                WKUserScript(source: script.wrappedSource(),
                             injectionTime: script.runAt == .documentStart ? .atDocumentStart : .atDocumentEnd,
                             forMainFrameOnly: !script.allFrames))
        }
    }

    func reloadSlip() {
        loadSlip()
        activeWebView?.reload()
    }

    private static let safariUserAgent: String = {
        let webKit = Bundle(identifier: "com.apple.WebKit")?
            .infoDictionary?["CFBundleShortVersionString"] as? String ?? "605.1.15"
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let os = "\(v.majorVersion)_\(v.minorVersion)_\(v.patchVersion)"
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X \(os)) AppleWebKit/\(webKit) (KHTML, like Gecko) Version/\(webKit) Safari/\(webKit)"
    }()

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

    func applyPreset(_ name: String, on targetScreen: NSScreen? = nil) {
        let screen = targetScreen ?? NSScreen.main ?? self.screen ?? NSScreen.screens[0]
        guard let rect = config.resolveFrame(preset: name, on: screen) else { return }
        activePresetName = name
        setFrame(rect, display: true, animate: false)
    }

    func applyFrame(_ frame: FrameConfig) {
        if let preset = frame.preset {
            applyPreset(preset)
            return
        }
        guard !frame.isEmpty else { return }
        let screen = NSScreen.main ?? self.screen ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let next = FrameResolver.applyPartial(frame, to: self.frame, visible: visible)
        setFrame(next, display: true, animate: false)
    }

    func applyAutoFrameForCurrentDisplays() {
        let count = NSScreen.screens.count
        let name = config.frameAuto?.presetName(forScreenCount: count)
            ?? config.frame
            ?? activePresetName
            ?? config.launchPresetName(screenCount: count)
        applyPreset(name, on: NSScreen.main)
    }

    private func activateWebView(_ wv: WKWebView, key: String, animated: Bool) {
        guard key != activeKey else { return }
        findBar?.removeFromSuperview()
        findBar = nil
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

        bindProgress(to: wv)
    }

    var activeWebView: WKWebView? {
        activeKey.flatMap { sessions[$0] }
    }

    // MARK: Progress bar

    private func bindProgress(to wv: WKWebView) {
        guard progressBar != nil else { return }  // no bar configured — skip KVO setup entirely

        // KVO can fire off-main; the async hop means a stale update for a since-deactivated
        // session can land after a site switch, so re-check identity before applying it.
        progressObservation = wv.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                guard let self, self.activeWebView === webView else { return }
                self.handleProgress(webView.estimatedProgress, isLoading: webView.isLoading)
            }
        }
        loadingObservation = wv.observe(\.isLoading, options: [.new]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                guard let self, self.activeWebView === webView else { return }
                self.handleProgress(webView.estimatedProgress, isLoading: webView.isLoading)
            }
        }
        // Sync instantly to whatever state the newly-active session is already in —
        // no animation, so switching sites doesn't trigger a distracting slide.
        handleProgress(wv.estimatedProgress, isLoading: wv.isLoading, animated: false)
    }

    private func handleProgress(_ progress: Double, isLoading: Bool, animated: Bool = true) {
        guard progressBarWidthConstraint != nil else { return }
        progressCollapseWorkItem?.cancel()
        if isLoading {
            setProgressBarFraction(progress, animated: animated)
        } else {
            setProgressBarFraction(1, animated: animated)
            let collapse = DispatchWorkItem { [weak self] in self?.setProgressBarFraction(0, animated: true) }
            progressCollapseWorkItem = collapse
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: collapse)
        }
    }

    private func setProgressBarFraction(_ fraction: Double, animated: Bool) {
        let width = contentView!.bounds.width * CGFloat(max(0, min(1, fraction)))
        progressBarWidthConstraint.constant = width
        guard animated else { contentView!.layoutSubtreeIfNeeded(); return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.allowsImplicitAnimation = true
            contentView!.layoutSubtreeIfNeeded()
        }
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

    // MARK: Public API — addressable sites

    /// `site <id>[/path]`: switch to the site's session; with a path, deep-link inside it.
    @discardableResult
    func openSite(id: String, path: String?) throws -> SiteConfig {
        guard let site = store.site(id: id) else {
            throw UrError("no site '\(id)' in pot '\(pot.name)' (list them with: ur-browse \(pot.name) sites --list)")
        }
        switchToSite(site)
        if let path, let url = URL(string: SiteStore.deepURL(base: site.url, path: path)) {
            activeWebView?.load(URLRequest(url: url))
        }
        return site
    }

    func siteListing() -> [SiteInfo] {
        let shortcuts = store.shortcutURLMap()
        let activeID = activeSite?.id
        return availableSites.map { site in
            SiteInfo(id: site.id ?? "", name: site.name, url: site.url,
                     shortcut: shortcuts[site.url], temporary: site.temporary,
                     open: sessions[siteKey(for: site.url)] != nil,
                     active: site.id == activeID,
                     address: BrowseAddress.site(pot: pot.name, id: site.id ?? ""))
        }
    }

    /// The configured/temporary site whose session is in front, if any.
    var activeSite: SiteConfig? {
        guard let activeKey else { return nil }
        return availableSites.first { siteKey(for: $0.url) == activeKey }
    }

    func currentInfo() -> CurrentInfo {
        let wv = activeWebView
        let url = wv?.url?.absoluteString
        return CurrentInfo(pot: pot.name, site: activeSite?.id, name: activeSite?.name,
                           url: (url == "about:blank") ? activeSite?.url : url,
                           title: wv?.title, visible: isVisible,
                           address: activeSite.flatMap { $0.id }.map { BrowseAddress.site(pot: pot.name, id: $0) })
    }

    private func copyCurrentURL() {
        guard let wv = activeWebView else { return }
        resolvePageURL(from: wv) { url in
            guard let url else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
        }
    }

    private func openInExternalBrowser() {
        guard let wv = activeWebView else { return }
        resolvePageURL(from: wv) { [weak self] url in
            guard let self, let url else { return }
            self.openURL(url, in: self.config.externalBrowser)
        }
    }

    private func resolvePageURL(from wv: WKWebView, completion: @escaping (URL?) -> Void) {
        if let url = wv.url, url.absoluteString != "about:blank" {
            completion(url)
            return
        }
        wv.evaluateJavaScript("location.href") { result, _ in
            let href = result as? String
            DispatchQueue.main.async {
                completion(href.flatMap(URL.init(string:)))
            }
        }
    }

    private func openURL(_ url: URL, in browser: String) {
        let ws = NSWorkspace.shared
        let openConfig: NSWorkspace.OpenConfiguration = {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            return cfg
        }()

        if let appURL = Self.resolveBrowserAppURL(named: browser) {
            ws.open([url], withApplicationAt: appURL, configuration: openConfig)
            return
        }
        ws.open(url, configuration: openConfig)
    }

    private static let browserBundleIDs: [String: String] = [
        "Safari": "com.apple.Safari",
        "Chrome": "com.google.Chrome",
        "Google Chrome": "com.google.Chrome",
        "Firefox": "org.mozilla.firefox",
        "Arc": "company.thebrowser.Browser",
        "Microsoft Edge": "com.microsoft.edgemac",
        "Brave": "com.brave.Browser",
    ]

    private static func resolveBrowserAppURL(named browser: String) -> URL? {
        let ws = NSWorkspace.shared
        if browser.contains(".") {
            if let url = ws.urlForApplication(withBundleIdentifier: browser) { return url }
        }
        if let bundleID = browserBundleIDs[browser],
           let url = ws.urlForApplication(withBundleIdentifier: bundleID) { return url }
        for dir in ["/Applications", "\(NSHomeDirectory())/Applications", "/System/Applications"] {
            let path = "\(dir)/\(browser).app"
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    func load(_ urlString: String) {
        if let matched = store.site(matching: urlString) {
            switchToSite(matched)
            if let url = URL(string: urlString) { activeWebView?.load(URLRequest(url: url)) }
        } else if let url = URL(string: urlString), let wv = activeWebView {
            wv.load(URLRequest(url: url))
        }
    }
    func show() {
        makeKeyAndOrderFront(nil)
        if !pickerVisible { makeFirstResponder(activeWebView) }
    }
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
        reloadSites()
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
        } else {
            makeFirstResponder(activeWebView)
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
        if let site = store.site(forURL: url) {
            switchToSite(site)
        } else {
            openURL(url)
        }
    }

    // MARK: Edit shortcuts (incl. 1Password concealed pasteboard)

    /// Password managers tag clipboard data as concealed; WKWebView often ignores it unless
    /// another app pastes first (which strips the markers). Read plain text in AppKit and inject.
    private static let concealedPasteboardTypes: [NSPasteboard.PasteboardType] = [
        .init("org.nspasteboard.ConcealedType"),
        .init("com.agilebits.onepassword"),
    ]

    private func handleEditShortcut(_ ch: String, event: NSEvent) -> Bool {
        if ch == "v", pasteboardHasConcealedMarkers(), let raw = plainStringOnPasteboard() {
            // 1Password often adds a trailing newline; React forms submit the literal string.
            let text = raw.trimmingCharacters(in: .newlines)
            return pasteNormalizedPlainText(text, event: event)
        }
        let action: Selector? = switch ch {
        case "c": #selector(NSText.copy(_:))
        case "v": #selector(NSText.paste(_:))
        case "x": #selector(NSText.cut(_:))
        case "a": #selector(NSText.selectAll(_:))
        case "z": Selector("undo:")
        default: nil
        }
        guard let action else { return false }
        return NSApp.sendAction(action, to: nil, from: event)
    }

    private func pasteboardHasConcealedMarkers() -> Bool {
        guard let types = NSPasteboard.general.types else { return false }
        return Self.concealedPasteboardTypes.contains(where: types.contains)
    }

    private func plainStringOnPasteboard() -> String? {
        let pb = NSPasteboard.general
        for type in [NSPasteboard.PasteboardType.string, .init("public.utf8-plain-text")] {
            if let s = pb.string(forType: type), !s.isEmpty { return s }
        }
        guard let s = pb.readObjects(forClasses: [NSString.self], options: nil)?.first as? String,
              !s.isEmpty else { return nil }
        return s
    }

    /// Strip 1Password concealed markers by rewriting plain text to the pasteboard, then use
    /// WebKit's normal paste (same effect as pasting through TextEdit first).
    @discardableResult
    private func pasteNormalizedPlainText(_ text: String, event: NSEvent) -> Bool {
        if pickerVisible, let editor = pickerView.searchField.currentEditor() {
            editor.replaceCharacters(in: editor.selectedRange, with: text)
            return true
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: event) {
            return true
        }
        return injectPlainTextIntoWebView(text)
    }

    @discardableResult
    private func injectPlainTextIntoWebView(_ text: String) -> Bool {
        guard let wv = activeWebView,
              let encoded = try? JSONEncoder().encode(text),
              let json = String(data: encoded, encoding: .utf8) else { return false }
        let script = """
        (function(t){
          var el=document.activeElement;
          if(!el) return false;
          function setValue(node,val){
            var proto=node.tagName==='TEXTAREA'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;
            var setter=Object.getOwnPropertyDescriptor(proto,'value').set;
            setter.call(node,val);
            node.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertFromPaste',data:val}));
            node.dispatchEvent(new Event('change',{bubbles:true}));
          }
          if(el.isContentEditable){document.execCommand('insertText',false,t);return true;}
          if(el.tagName==='INPUT'||el.tagName==='TEXTAREA'){
            var s=el.selectionStart!=null?el.selectionStart:el.value.length;
            var e=el.selectionEnd!=null?el.selectionEnd:el.value.length;
            setValue(el,el.value.slice(0,s)+t+el.value.slice(e));
            el.selectionStart=el.selectionEnd=s+t.length;
            return true;
          }
          return false;
        })(\(json));
        """
        wv.evaluateJavaScript(script)
        return true
    }

    // NSPanel with .nonactivatingPanel can only become key if it has .titled or a toolbar.
    // We have neither in chrome-free mode, so we override explicitly.
    override var canBecomeKey: Bool { true }
    // Take keyboard focus without claiming "main window" status from the app's real window.
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, pickerVisible { hideSitePicker() }
        else { super.keyDown(with: event) }
    }

    // MARK: Find bar

    private func showFindBar() {
        if findBar == nil {
            let bar = FindBarView()
            bar.translatesAutoresizingMaskIntoConstraints = false
            bar.onFind       = { [weak self] text, backwards in self?.doFind(text, backwards: backwards) }
            bar.onTextChange = { [weak self] text in self?.countMatches(text) }
            bar.onClose      = { [weak self] in self?.hideFindBar() }
            webContainer.addSubview(bar)
            NSLayoutConstraint.activate([
                bar.bottomAnchor.constraint(equalTo: webContainer.bottomAnchor),
                bar.leadingAnchor.constraint(equalTo: webContainer.leadingAnchor),
                bar.trailingAnchor.constraint(equalTo: webContainer.trailingAnchor),
                bar.heightAnchor.constraint(equalToConstant: 40),
            ])
            findBar = bar
            injectFindCSS()
        }
        makeFirstResponder(findBar?.searchField)
    }

    private func hideFindBar() {
        removeFindCSS()
        findBar?.removeFromSuperview()
        findBar = nil
        makeFirstResponder(activeWebView)
    }

    private func doFind(_ text: String, backwards: Bool) {
        guard !text.isEmpty, let wv = activeWebView else { return }
        let cfg = WKFindConfiguration()
        cfg.backwards = backwards
        cfg.wraps = true
        cfg.caseSensitive = false
        wv.find(text, configuration: cfg) { [weak self] result in
            if !result.matchFound { self?.findBar?.showStatus("No results", isError: true) }
        }
    }

    private func countMatches(_ text: String) {
        guard !text.isEmpty else { findBar?.showStatus("", isError: false); return }
        guard let wv = activeWebView else { return }
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        let js = #"""
        (() => { try {
            const t = "\#(escaped)";
            const re = new RegExp(t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'gi');
            return ((document.body && document.body.innerText) || '').match(re)?.length || 0;
        } catch(e) { return 0; } })()
        """#
        wv.evaluateJavaScript(js) { [weak self] result, _ in
            let n = (result as? NSNumber)?.intValue ?? 0
            let label = n == 0 ? "No results" : "\(n) match\(n == 1 ? "" : "es")"
            self?.findBar?.showStatus(label, isError: n == 0)
        }
    }

    private func injectFindCSS() {
        guard let wv = activeWebView else { return }
        let js = #"""
        (() => {
            if (document.getElementById('_gf')) return;
            const s = document.createElement('style');
            s.id = '_gf';
            s.textContent = '*::selection{background:rgba(255,140,0,.75)!important;color:inherit!important}';
            (document.head || document.documentElement).appendChild(s);
        })()
        """#
        wv.evaluateJavaScript(js) { _, _ in }
    }

    private func removeFindCSS() {
        activeWebView?.evaluateJavaScript("document.getElementById('_gf')?.remove()") { _, _ in }
    }

    // MARK: Chrome — toolbar & color stripe

    private func setupToolbar() {
        let tb = NSToolbar(identifier: "UrBrowse-\(config.name)")
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
