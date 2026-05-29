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
    private var findBar: FindBarView?

    // Site cycling
    private var activeSiteIndex: Int = 0

    private(set) var activePresetName: String?

    private var titleObservation: NSKeyValueObservation?

    init(config: AppConfig) {
        self.config = config

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
            let ch = event.charactersIgnoringModifiers
            if cmd && !shift && noExtra && ch == "r" { self.activeWebView?.reload(); return nil }
            if cmd && !shift && noExtra && ch == "[" { self.activeWebView?.goBack(); return nil }
            if cmd && !shift && noExtra && ch == "]" { self.activeWebView?.goForward(); return nil }
            // Shift produces "O" not "o" in charactersIgnoringModifiers.
            if cmd && shift && noExtra && self.isKeyWindow && ch?.lowercased() == "o" {
                self.openInExternalBrowser(); return nil
            }
            if cmd && !shift && noExtra, let ch, ch.count == 1, let n = Int(ch) {
                if n == 0 {
                    self.openURL(self.config.defaultUrl, animated: true)
                    return nil
                }
                if (1...9).contains(n),
                   self.config.pinned != nil || !self.transientShortcuts.isEmpty {
                    self.activateShortcut(n)
                    return nil
                }
            }
            // Non-activating panel: active app's menu bar still owns ⌘C/⌘V unless we intercept.
            if event.keyCode == 53 && self.findBar != nil { self.hideFindBar(); return nil }
            if cmd && !shift && noExtra && ch == "f" { self.showFindBar(); return nil }
            if cmd && noExtra && ch == "g" && self.findBar != nil {
                self.doFind(self.findBar!.searchText, backwards: shift); return nil
            }
            if cmd && shift && noExtra && self.isKeyWindow && ch == "z" {
                NSApp.sendAction(Selector("redo:"), to: nil, from: event); return nil
            }
            if cmd && !shift && noExtra && self.isKeyWindow, let ch,
               self.handleEditShortcut(ch, event: event) { return nil }
            return event
        }

        openURL(config.defaultUrl, animated: false)
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
        // Default WKWebView UA omits "Version/… Safari/…"; some login flows reject that.
        wv.customUserAgent = Self.safariUserAgent
        wv.enableInspection()
        return wv
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
        if let matched = siteMatchingURL(urlString) {
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
        if let site = site(namedByURL: url) {
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

private final class FindBarView: NSView, NSSearchFieldDelegate {
    private let field  = NSSearchField()
    private let status = NSTextField(labelWithString: "")
    var onFind:       ((String, Bool) -> Void)?
    var onTextChange: ((String) -> Void)?
    var onClose:      (() -> Void)?
    var searchText:  String        { field.stringValue }
    var searchField: NSSearchField { field }

    override init(frame: NSRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { nil }

    func controlTextDidChange(_ obj: Notification) {
        let text = field.stringValue
        status.stringValue = ""
        onFind?(text, false)
        onTextChange?(text)
    }

    func showStatus(_ text: String, isError: Bool) {
        status.stringValue = text
        status.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    private func setup() {
        let bg = NSVisualEffectView()
        bg.material = .hudWindow
        bg.blendingMode = .withinWindow
        bg.state = .active
        bg.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bg)

        let border = NSView()
        border.wantsLayer = true
        border.layer?.backgroundColor = NSColor.separatorColor.cgColor
        border.translatesAutoresizingMaskIntoConstraints = false
        addSubview(border)

        field.delegate = self
        field.target = self
        field.action = #selector(findNext)
        field.placeholderString = "Find in page…"
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)

        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.textColor = .secondaryLabelColor
        status.translatesAutoresizingMaskIntoConstraints = false
        addSubview(status)

        func btn(_ sym: String, _ desc: String, _ sel: Selector) -> NSButton {
            let b = NSButton()
            b.image = NSImage(systemSymbolName: sym, accessibilityDescription: desc)
            b.isBordered = false
            b.target = self
            b.action = sel
            b.translatesAutoresizingMaskIntoConstraints = false
            addSubview(b)
            return b
        }
        let prev  = btn("chevron.up",   "Previous", #selector(findPrev))
        let next  = btn("chevron.down", "Next",     #selector(findNext))
        let close = btn("xmark",        "Close",    #selector(closeBar))

        NSLayoutConstraint.activate([
            bg.topAnchor.constraint(equalTo: topAnchor),
            bg.bottomAnchor.constraint(equalTo: bottomAnchor),
            bg.leadingAnchor.constraint(equalTo: leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: trailingAnchor),
            border.topAnchor.constraint(equalTo: topAnchor),
            border.leadingAnchor.constraint(equalTo: leadingAnchor),
            border.trailingAnchor.constraint(equalTo: trailingAnchor),
            border.heightAnchor.constraint(equalToConstant: 1),
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
            field.widthAnchor.constraint(equalToConstant: 160),
            status.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: 6),
            status.centerYAnchor.constraint(equalTo: centerYAnchor),
            status.widthAnchor.constraint(equalToConstant: 72),
            prev.leadingAnchor.constraint(equalTo: status.trailingAnchor, constant: 4),
            prev.centerYAnchor.constraint(equalTo: centerYAnchor),
            next.leadingAnchor.constraint(equalTo: prev.trailingAnchor, constant: 2),
            next.centerYAnchor.constraint(equalTo: centerYAnchor),
            close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            close.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @objc private func findNext() { onFind?(field.stringValue, false) }
    @objc private func findPrev() { onFind?(field.stringValue, true) }
    @objc private func closeBar() { onClose?() }
}
