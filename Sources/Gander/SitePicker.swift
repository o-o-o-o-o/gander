import AppKit

// Embedded picker view — lives inside SidebarPanel, slides down from the top.
// SidebarPanel owns the height constraint and drives the animation.
class SitePickerView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private(set) var searchField: NSSearchField!
    private var tableView: NSTableView!
    private var allSites: [SiteConfig] = []
    private var filtered: [SiteConfig] = []

    var onSelect:  ((String) -> Void)?
    var onDismiss: (() -> Void)?

    private var urlSuggestion: String? {
        let text = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.contains(".") || text.contains("://"), !text.contains(" ") else { return nil }
        return text.contains("://") ? text : "https://\(text)"
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Clip so content disappears cleanly when height animates to 0
        wantsLayer = true
        layer?.masksToBounds = true
        setupUI()
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(sites: [SiteConfig]) {
        allSites = sites
        filtered = sites
    }

    // Call before showing to reset search state
    func prepare() {
        filtered = allSites
        searchField.stringValue = ""
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    }

    private func setupUI() {
        // Frosted-glass background
        let fx = NSVisualEffectView()
        fx.material = .sidebar
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fx)
        NSLayoutConstraint.activate([
            fx.topAnchor.constraint(equalTo: topAnchor),
            fx.bottomAnchor.constraint(equalTo: bottomAnchor),
            fx.leadingAnchor.constraint(equalTo: leadingAnchor),
            fx.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        // Search field
        searchField = NSSearchField()
        searchField.placeholderString = "Go to site…"
        searchField.font = .systemFont(ofSize: 14)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.delegate = self
        fx.addSubview(searchField)

        let sep = NSBox(); sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        fx.addSubview(sep)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        tableView = NSTableView()
        let col = NSTableColumn(identifier: .init("site"))
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.rowHeight = 36
        tableView.dataSource = self
        tableView.delegate = self
        tableView.doubleAction = #selector(confirm)
        tableView.target = self
        scroll.documentView = tableView
        fx.addSubview(scroll)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: fx.topAnchor, constant: 10),
            searchField.leadingAnchor.constraint(equalTo: fx.leadingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: fx.trailingAnchor, constant: -10),

            sep.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            sep.leadingAnchor.constraint(equalTo: fx.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: fx.trailingAnchor),

            scroll.topAnchor.constraint(equalTo: sep.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: fx.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: fx.bottomAnchor),
        ])
    }

    @objc private func confirm() {
        let row = tableView.selectedRow
        guard row >= 0 else { return }
        if row == filtered.count, let url = urlSuggestion {
            onSelect?(url)
            return
        }
        guard row < filtered.count else { return }
        onSelect?(filtered[row].url)
    }

    // MARK: Table data source

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count + (urlSuggestion != nil ? 1 : 0) }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 13)
        let sub = NSTextField(labelWithString: "")
        sub.font = .systemFont(ofSize: 11)
        sub.textColor = .secondaryLabelColor

        if row == filtered.count, let url = urlSuggestion {
            label.stringValue = "Open URL"
            sub.stringValue = url
        } else {
            let site = filtered[row]
            label.stringValue = site.temporary ? "\(site.name) ~" : site.name
            sub.stringValue = site.url
        }

        [label, sub].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview($0) }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            label.topAnchor.constraint(equalTo: cell.topAnchor, constant: 3),
            sub.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            sub.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 1),
        ])
        return cell
    }
}

// MARK: Search field delegate — arrow keys navigate the table without leaving the field
extension SitePickerView: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        let q = searchField.stringValue.lowercased()
        filtered = q.isEmpty ? allSites : allSites.filter {
            $0.name.lowercased().contains(q) || $0.url.lowercased().contains(q)
        }
        tableView.reloadData()
        let total = filtered.count + (urlSuggestion != nil ? 1 : 0)
        if total > 0 {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(moveDown(_:)):
            let next = min(tableView.selectedRow + 1, filtered.count - 1)
            tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
            tableView.scrollRowToVisible(next)
            return true
        case #selector(moveUp(_:)):
            let prev = max(tableView.selectedRow - 1, 0)
            tableView.selectRowIndexes(IndexSet(integer: prev), byExtendingSelection: false)
            tableView.scrollRowToVisible(prev)
            return true
        case #selector(insertNewline(_:)):
            confirm(); return true
        case #selector(cancelOperation(_:)):
            onDismiss?(); return true
        default:
            return false
        }
    }
}
