import AppKit
import WebKit

private let PICKER_HEIGHT: CGFloat = 260

class SidebarPanel: NSPanel, NSToolbarDelegate {
    private let config: AppConfig
    private var transientSites: [SiteConfig] = []

    // One persistent WKWebView per site — sessions survive site switches
    private var sessions:  [String: WKWebView] = [:]   // keyed by site.url
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
        isMovableByWindowBackground = !config.chrome  // drag anywhere when chrome-free

        if config.chrome { setupToolbar() }

        setupLayout()  // must come after toolbar so contentView top is below toolbar

        // ⌘R reload — local monitor fires only when our app is active; no global permission needed
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  event.modifierFlags.contains(.command),
                  event.modifierFlags.intersection([.shift, .option, .control]).isEmpty,
                  event.charactersIgnoringModifiers == "r" else { return event }
            self.activeWebView?.reload()
            return nil
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

    private func refreshPickerSites() {
        pickerView.configure(sites: availableSites)
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

    func load(_ urlString: String) { openURL(urlString) }
    func show()   { makeKeyAndOrderFront(nil) }
    func hide()   { orderOut(nil) }
    func toggle() { if isVisible { hide() } else { show() } }

    // MARK: Site picker

    func showSitePicker() {
        makeKeyAndOrderFront(nil)   // always steal focus so keyboard works immediately
        guard !pickerVisible else { return }
        pickerVisible = true
        pickerView.prepare()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            pickerHeightConstraint.animator().constant = PICKER_HEIGHT
        }
        DispatchQueue.main.async { [weak self] in
            self?.makeFirstResponder(self?.pickerView.searchField)
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
