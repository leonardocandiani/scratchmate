import AppKit

/// "What's New" panel, shown once after the app updates to a new version. The
/// notes ship in a bundled WhatsNew.md (rewritten on every release so they always
/// match the build); the panel is gated on a version change so it never nags and
/// never shows stale notes.
///
/// Gating uses plain UserDefaults: "lastWhatsNewVersion" (the last version whose
/// notes the user saw) compared against the running CFBundleShortVersionString,
/// and "hasLaunchedBefore" so a fresh install never sees it (the welcome card
/// runs instead). Keys are read and written here directly, not through Settings,
/// to stay clear of the preferences layer.
final class WhatsNewWindowController: NSObject, NSWindowDelegate {

    private static let lastSeenKey = "lastWhatsNewVersion"
    private static let hasLaunchedKey = "hasLaunchedBefore"

    private var window: NSWindow?

    private let cardWidth: CGFloat = 460
    private let cardHeight: CGFloat = 540

    // MARK: - Version + storage

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    private var lastSeenVersion: String {
        get { UserDefaults.standard.string(forKey: Self.lastSeenKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastSeenKey) }
    }

    private var hasLaunchedBefore: Bool {
        UserDefaults.standard.bool(forKey: Self.hasLaunchedKey)
    }

    // MARK: - Notes model

    private struct Notes {
        let version: String
        let body: String
    }

    /// Parses the bundled WhatsNew.md: an optional leading `version: X.Y.Z` line,
    /// then the markdown body. Returns nil when the file is missing or empty.
    private func loadNotes() -> Notes? {
        guard let url = Bundle.main.url(forResource: "WhatsNew", withExtension: "md"),
              let raw = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }

        var lines = raw.components(separatedBy: "\n")
        var version = ""
        if let first = lines.first, first.lowercased().hasPrefix("version:") {
            version = String(first.dropFirst("version:".count)).trimmingCharacters(in: .whitespaces)
            lines.removeFirst()
        }
        let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        return Notes(version: version, body: body)
    }

    /// Pure decision: show once per version, only after an update (never on a
    /// fresh install, where the welcome runs), and never for stale notes whose
    /// version does not match the running build.
    private func shouldShow(current: String, lastSeen: String, hasLaunched: Bool, notesVersion: String) -> Bool {
        guard hasLaunched else { return false }
        guard !current.isEmpty, lastSeen != current else { return false }
        return notesVersion == current
    }

    // MARK: - Entry points

    /// Automatic: shown at launch when the version changed since last seen.
    /// Marks the current version as seen on every path so it never re-triggers.
    func showIfNeeded() {
        guard Settings.showWhatsNewAfterUpdate else { return }  // user can opt out
        let current = appVersion
        defer { lastSeenVersion = current }
        guard let notes = loadNotes() else { return }
        guard shouldShow(
            current: current, lastSeen: lastSeenVersion,
            hasLaunched: hasLaunchedBefore, notesVersion: notes.version
        ) else { return }
        present(notes: notes)
    }

    /// Manual (menu): always shows whatever notes ship in this build, if any.
    func showManually() {
        guard let notes = loadNotes() else { return }
        present(notes: notes)
        lastSeenVersion = appVersion
    }

    // MARK: - Window

    private func present(notes: Notes) {
        window?.close()

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: cardWidth, height: cardHeight),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "What's New"
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        // Match the active theme so the card honours the app appearance.
        win.appearance = NSAppearance(named: Theme.byID(Settings.themeID).isDark ? .darkAqua : .aqua)
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self

        // Content lives in a container that becomes the glass contentView.
        let content = NSView(frame: NSRect(x: 0, y: 0, width: cardWidth, height: cardHeight))
        let version = notes.version.isEmpty ? appVersion : notes.version
        buildContent(in: content, version: version, markdown: notes.body)
        let background = GlassBackground.panel(wrapping: content, cornerRadius: GlassBackground.Radius.panel)
        background.frame = NSRect(x: 0, y: 0, width: cardWidth, height: cardHeight)
        background.autoresizingMask = [.width, .height]
        win.contentView = background

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        window = win
    }

    // MARK: - Content

    private func buildContent(in container: NSView, version: String, markdown: String) {
        let w = container.bounds.width

        // Header: sparkles glyph, title, version.
        let headerTop = container.bounds.height - 28

        let glyph = NSImageView(frame: NSRect(x: (w - 34) / 2, y: headerTop - 34, width: 34, height: 34))
        glyph.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "What's New")
        glyph.symbolConfiguration = Typography.symbolConfig(pointSize: 28, weight: .semibold)
        glyph.contentTintColor = DesignTokens.accent
        container.addSubview(glyph)

        let title = NSTextField(labelWithString: "What's New")
        title.font = .boldSystemFont(ofSize: 22)
        title.textColor = DesignTokens.label
        title.alignment = .center
        title.frame = NSRect(x: 20, y: headerTop - 34 - 32, width: w - 40, height: 26)
        container.addSubview(title)

        let versionLabel = NSTextField(labelWithString: "ScratchMate \(version)")
        versionLabel.font = .systemFont(ofSize: 12, weight: .medium)
        versionLabel.textColor = DesignTokens.secondaryLabel
        versionLabel.alignment = .center
        versionLabel.frame = NSRect(x: 20, y: headerTop - 34 - 32 - 22, width: w - 40, height: 16)
        container.addSubview(versionLabel)

        // Footer: hairline + primary action.
        let footerHeight: CGFloat = 64

        let separator = NSBox()
        separator.boxType = .separator
        separator.frame = NSRect(x: 24, y: footerHeight, width: w - 48, height: 1)
        separator.autoresizingMask = [.width]
        container.addSubview(separator)

        let continueButton = NSButton(title: "Continue", target: self, action: #selector(continueClicked))
        continueButton.bezelStyle = .rounded
        continueButton.controlSize = .large
        continueButton.bezelColor = DesignTokens.accent
        continueButton.keyEquivalent = "\r"
        continueButton.frame = NSRect(x: 24, y: (footerHeight - 34) / 2, width: w - 48, height: 34)
        continueButton.autoresizingMask = [.width]
        container.addSubview(continueButton)

        // Scrollable notes between header and footer.
        let contentTop = headerTop - 34 - 32 - 22 - 14
        let scrollFrame = NSRect(
            x: 0, y: footerHeight + 1,
            width: w, height: contentTop - (footerHeight + 1)
        )
        let scroll = NSScrollView(frame: scrollFrame)
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.autoresizingMask = [.width, .height]

        let document = makeNotesDocument(markdown: markdown, width: w)
        scroll.documentView = document
        container.addSubview(scroll)
        // Flipped document: top of the notes is at the origin, so show it from
        // the top. Defer one pass so the clip view has its final geometry.
        DispatchQueue.main.async { scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView) }
    }

    /// Renders the markdown body into a stacked flipped document view: `##`
    /// headings, `-`/`*` bullets, and inline `**bold**`. Lays out top to bottom.
    private func makeNotesDocument(markdown: String, width: CGFloat) -> NSView {
        let document = FlippedView()
        let contentWidth = width
        let leftInset: CGFloat = 28
        var y: CGFloat = 16

        for rawLine in markdown.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                y += 8
                continue
            }

            if line.hasPrefix("## ") {
                let text = String(line.dropFirst(3))
                let field = NSTextField(labelWithString: text)
                field.font = .systemFont(ofSize: 14, weight: .semibold)
                field.textColor = DesignTokens.label
                field.lineBreakMode = .byWordWrapping
                field.maximumNumberOfLines = 0
                field.preferredMaxLayoutWidth = contentWidth - leftInset * 2
                let h = field.sizeThatFits(NSSize(width: contentWidth - leftInset * 2, height: .greatestFiniteMagnitude)).height
                field.frame = NSRect(x: leftInset, y: y + 6, width: contentWidth - leftInset * 2, height: h)
                document.addSubview(field)
                y += h + 12
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                let text = String(line.dropFirst(2))
                let dot = NSView(frame: NSRect(x: leftInset + 2, y: y + 6, width: 5, height: 5))
                dot.wantsLayer = true
                dot.layer?.backgroundColor = DesignTokens.accent.cgColor
                dot.layer?.cornerRadius = 2.5
                document.addSubview(dot)

                let field = NSTextField(labelWithString: "")
                field.attributedStringValue = inlineAttributed(text, size: 13)
                field.lineBreakMode = .byWordWrapping
                field.maximumNumberOfLines = 0
                let textX = leftInset + 14
                let textW = contentWidth - textX - leftInset
                field.preferredMaxLayoutWidth = textW
                let h = field.sizeThatFits(NSSize(width: textW, height: .greatestFiniteMagnitude)).height
                field.frame = NSRect(x: textX, y: y, width: textW, height: h)
                document.addSubview(field)
                y += h + 8
            } else {
                let field = NSTextField(labelWithString: "")
                field.attributedStringValue = inlineAttributed(line, size: 13)
                field.lineBreakMode = .byWordWrapping
                field.maximumNumberOfLines = 0
                field.preferredMaxLayoutWidth = contentWidth - leftInset * 2
                let h = field.sizeThatFits(NSSize(width: contentWidth - leftInset * 2, height: .greatestFiniteMagnitude)).height
                field.frame = NSRect(x: leftInset, y: y, width: contentWidth - leftInset * 2, height: h)
                document.addSubview(field)
                y += h + 8
            }
        }

        document.frame = NSRect(x: 0, y: 0, width: width, height: y + 16)
        return document
    }

    /// Builds an attributed string for a body line, bolding `**…**` runs and
    /// leaving the rest at the regular weight.
    private func inlineAttributed(_ source: String, size: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let regular: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size),
            .foregroundColor: DesignTokens.label.withAlphaComponent(0.9),
        ]
        let bold: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: DesignTokens.label,
        ]

        let segments = source.components(separatedBy: "**")
        for (i, segment) in segments.enumerated() {
            // Odd segments sit between a pair of ** markers, so they are bold.
            let bolded = i % 2 == 1
            result.append(NSAttributedString(string: segment, attributes: bolded ? bold : regular))
        }
        return result
    }

    // MARK: - Actions

    @objc private func continueClicked() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

/// A top-left origin container, so notes lay out from the top down. NSScrollView
/// is bottom-left by default; this flips the document so y grows downward.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
