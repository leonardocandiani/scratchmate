import AppKit
import ScratchMateCore

/// A clickable result row that holds the note and highlights on hover.
final class NoteRowView: NSView {
    var note: Note?
    var accent: NSColor = .controlAccentColor
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(t); tracking = t
    }

    override func mouseEntered(with event: NSEvent) {
        wantsLayer = true
        layer?.backgroundColor = accent.withAlphaComponent(0.14).cgColor
    }
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

/// Search (⌘F) in the Antinote style: a top bar and a list of every note, filtering
/// as you type. Enter opens the first result, a click opens the chosen one, Esc cancels.
final class SearchController: NSViewController {
    private let database: Database?
    private let theme: Theme
    var onPick: ((Note) -> Void)?
    var onCancel: (() -> Void)?

    private let field = NSSearchField()
    private let cancelButton = NSButton()
    private let resultsStack = NSStackView()
    private let scroll = NSScrollView()
    private var results: [Note] = []
    private var debounce: DispatchWorkItem?

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "en_US")
        f.unitsStyle = .full
        return f
    }()

    init(database: Database?, theme: Theme) {
        self.database = database
        self.theme = theme
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        // All content lives in a container that becomes the glass contentView.
        let content = NSView()

        // TintView (not a plain layer color) so the tint survives an appearance switch.
        let tint = TintView()
        tint.fillColor = theme.backgroundColor.withAlphaComponent(0.9)
        tint.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(tint)

        field.placeholderString = "Search all notes"
        field.font = .systemFont(ofSize: 15)
        field.delegate = self
        field.focusRingType = .none
        field.translatesAutoresizingMaskIntoConstraints = false

        cancelButton.title = "Cancel"
        cancelButton.isBordered = false
        cancelButton.bezelStyle = .accessoryBar
        cancelButton.contentTintColor = theme.accentColor
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.setContentHuggingPriority(.required, for: .horizontal)

        let header = NSStackView(views: [field, cancelButton])
        header.orientation = .horizontal
        header.spacing = 10
        header.translatesAutoresizingMaskIntoConstraints = false

        resultsStack.orientation = .vertical
        resultsStack.spacing = 0
        resultsStack.alignment = .leading
        resultsStack.translatesAutoresizingMaskIntoConstraints = false

        let docView = NSView()
        docView.translatesAutoresizingMaskIntoConstraints = false
        docView.addSubview(resultsStack)
        scroll.documentView = docView
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.hasVerticalScroller = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(header)
        content.addSubview(scroll)

        NSLayoutConstraint.activate([
            tint.topAnchor.constraint(equalTo: content.topAnchor),
            tint.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            tint.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            header.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            resultsStack.topAnchor.constraint(equalTo: docView.topAnchor),
            resultsStack.leadingAnchor.constraint(equalTo: docView.leadingAnchor),
            resultsStack.trailingAnchor.constraint(equalTo: docView.trailingAnchor),
            resultsStack.bottomAnchor.constraint(equalTo: docView.bottomAnchor),
            docView.widthAnchor.constraint(equalTo: scroll.widthAnchor),
        ])

        let root = GlassBackground.panel(wrapping: content, cornerRadius: GlassBackground.Radius.panel)
        root.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
        self.view = root
        reload(query: "")
    }

    func focusSearch() { view.window?.makeFirstResponder(field) }

    @objc private func cancel() { onCancel?() }

    private func reload(query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            results = (try? database?.recentNotes(limit: 200)) ?? []
        } else {
            results = (try? database?.search(q, limit: 200)) ?? []
        }
        rebuild()
    }

    private func rebuild() {
        resultsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard !results.isEmpty else {
            let empty = NSTextField(labelWithString: "No notes found")
            empty.font = .systemFont(ofSize: 13)
            empty.textColor = theme.secondaryColor
            empty.translatesAutoresizingMaskIntoConstraints = false
            let wrap = NSView()
            wrap.translatesAutoresizingMaskIntoConstraints = false
            wrap.addSubview(empty)
            NSLayoutConstraint.activate([
                empty.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 18),
                empty.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 16),
                empty.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -16),
            ])
            resultsStack.addArrangedSubview(wrap)
            wrap.widthAnchor.constraint(equalTo: resultsStack.widthAnchor).isActive = true
            return
        }
        for note in results {
            let row = makeRow(note)
            resultsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: resultsStack.widthAnchor).isActive = true
        }
    }

    private func makeRow(_ note: Note) -> NoteRowView {
        let row = NoteRowView()
        row.note = note
        row.accent = theme.accentColor
        row.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: note.title.isEmpty ? "[Untitled note]" : note.title)
        title.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        title.textColor = theme.foregroundColor
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1

        let time = NSTextField(labelWithString: Self.relative.localizedString(for: note.updatedAt, relativeTo: Date()))
        time.font = .systemFont(ofSize: 11)
        time.textColor = theme.secondaryColor

        let col = NSStackView(views: [title, time])
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 2
        col.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(col)
        NSLayoutConstraint.activate([
            col.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 18),
            col.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -18),
            col.topAnchor.constraint(equalTo: row.topAnchor, constant: 9),
            col.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -9),
        ])
        let click = NSClickGestureRecognizer(target: self, action: #selector(rowClicked(_:)))
        row.addGestureRecognizer(click)
        return row
    }

    @objc private func rowClicked(_ gr: NSClickGestureRecognizer) {
        guard let row = gr.view as? NoteRowView, let note = row.note else { return }
        onPick?(note)
    }
}

extension SearchController: NSSearchFieldDelegate {
    nonisolated func controlTextDidChange(_ obj: Notification) {
        MainActor.assumeIsolated {
            debounce?.cancel()
            let q = field.stringValue
            let work = DispatchWorkItem { [weak self] in self?.reload(query: q) }
            debounce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        }
    }

    nonisolated func control(
        _ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector
    ) -> Bool {
        MainActor.assumeIsolated {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                cancel(); return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if let first = results.first { onPick?(first) }
                return true
            }
            return false
        }
    }
}
