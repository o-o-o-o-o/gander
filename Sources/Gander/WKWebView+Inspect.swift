import WebKit

extension WKWebView {
    /// Expose this web view in Safari → Develop → [machine] → Gander (macOS 13.3+).
    func enableInspection() {
        if #available(macOS 13.3, *) {
            isInspectable = true
        }
    }
}
