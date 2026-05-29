import AppKit
import WebKit

extension WKWebView {
    /// Expose this web view in Safari → Develop → [machine] → Gander (macOS 13.3+).
    func enableInspection() {
        if #available(macOS 13.3, *) {
            isInspectable = true
        }
    }
}

/// WKWebView subclass with a custom right-click menu.
/// `willOpenMenu` is NOT called by WebKit on macOS — it uses an internal subview as the
/// `forView:` argument to `NSMenu.popUpContextMenu`, so overriding it on WKWebView has no
/// effect. Overriding `rightMouseDown` is the reliable alternative.
class GanderWebView: WKWebView {
    var onCopyURL:        (() -> Void)?
    var onOpenExternally: (() -> Void)?

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()

        if canGoBack    { menu.add("Back",    #selector(goBackAction),    target: self) }
        if canGoForward { menu.add("Forward", #selector(goForwardAction), target: self) }
        menu.add("Reload",   #selector(reloadAction), target: self)

        menu.addItem(.separator())
        menu.add("Copy URL", #selector(doCopyURL), target: self)

        let ext = NSMenuItem(title: "Open Externally", action: #selector(doOpenExternally), keyEquivalent: "O")
        ext.keyEquivalentModifierMask = [.command, .shift]
        ext.target = self
        menu.addItem(ext)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func goBackAction()     { _ = goBack() }
    @objc private func goForwardAction()  { _ = goForward() }
    @objc private func reloadAction()     { _ = reload() }
    @objc private func doCopyURL()        { onCopyURL?() }
    @objc private func doOpenExternally() { onOpenExternally?() }
}

private extension NSMenu {
    func add(_ title: String, _ sel: Selector, target: AnyObject? = nil) {
        let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        item.target = target
        addItem(item)
    }
}
