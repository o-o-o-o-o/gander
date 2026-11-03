import AppKit

/// Bottom-of-panel find bar (⌘F). Owned by SidebarPanel, which does the actual WKWebView
/// find work through the callbacks.
final class FindBarView: NSView, NSSearchFieldDelegate {
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
