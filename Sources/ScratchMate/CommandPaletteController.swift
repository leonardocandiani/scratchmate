import AppKit
import ScratchMateCore

/// Command palette: a search field plus a filterable list. Opens with ⌘K or by
/// typing `::` in the editor. Enter runs, arrows navigate, Esc closes.
final class CommandPaletteController: NSViewController {
    private let registry: CommandRegistry
    private var languageId: String = "markdown"
    private var results: [TextCommand] = []
    var onExecute: ((TextCommand) -> Void)?
    var onCancel: (() -> Void)?

    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()

    init(registry: CommandRegistry) {
        self.registry = registry
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        let content = NSView()

        searchField.placeholderString = "Command…  (e.g. ::sort, json, dedupe)"
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.focusRingType = .none
        content.addSubview(searchField)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("cmd"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 40
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(executeSelected)
        tableView.style = .inset

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        content.addSubview(scrollView)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
        ])

        let container = GlassBackground.panel(wrapping: content, cornerRadius: GlassBackground.Radius.panel)
        container.frame = NSRect(x: 0, y: 0, width: 520, height: 360)
        self.view = container
    }

    /// Resets the palette for a new invocation, with the active note's language.
    func prepare(languageId: String, initialQuery: String = "") {
        self.languageId = languageId
        searchField.stringValue = initialQuery
        reload(query: initialQuery)
    }

    func focusSearch() {
        view.window?.makeFirstResponder(searchField)
        if !results.isEmpty { tableView.selectRowIndexes([0], byExtendingSelection: false) }
    }

    private func reload(query: String) {
        results = registry.matches(prefix: query, languageId: languageId)
        tableView.reloadData()
        if !results.isEmpty {
            tableView.selectRowIndexes([0], byExtendingSelection: false)
        }
    }

    @objc private func executeSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < results.count else { return }
        onExecute?(results[row])
    }

    private func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        let current = max(tableView.selectedRow, 0)
        let next = min(max(current + delta, 0), results.count - 1)
        tableView.selectRowIndexes([next], byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }
}

extension CommandPaletteController: NSSearchFieldDelegate {
    nonisolated func controlTextDidChange(_ obj: Notification) {
        MainActor.assumeIsolated {
            reload(query: searchField.stringValue)
        }
    }

    nonisolated func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        MainActor.assumeIsolated {
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                moveSelection(by: -1); return true
            case #selector(NSResponder.moveDown(_:)):
                moveSelection(by: 1); return true
            case #selector(NSResponder.insertNewline(_:)):
                executeSelected(); return true
            case #selector(NSResponder.cancelOperation(_:)):
                onCancel?(); return true
            default:
                return false
            }
        }
    }
}

extension CommandPaletteController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cmdCell")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? PaletteCell) ?? PaletteCell(id: id)
        cell.configure(with: results[row])
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { true }
}

/// A cell with the trigger in mono and a descriptive title below.
private final class PaletteCell: NSTableCellView {
    private let triggerLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")

    init(id: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        identifier = id
        triggerLabel.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
        titleLabel.font = .systemFont(ofSize: 11)
        titleLabel.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [triggerLabel, titleLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(with command: TextCommand) {
        triggerLabel.stringValue = command.trigger
        titleLabel.stringValue = command.title
    }
}
