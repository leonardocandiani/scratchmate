import AppKit
import WebKit
import ScratchMateCore

/// Small panel that accepts keyboard focus, to host the palette as a childWindow.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Container with two hover zones: the bottom strip reveals the footer; the top
/// strip reveals the window buttons (traffic lights). Outside them, the window stays clean.
final class HoverView: NSView {
    var onHoverBottom: ((Bool) -> Void)?
    var onHoverTop: ((Bool) -> Void)?
    var bottomZoneHeight: CGFloat = 72
    var topZoneHeight: CGFloat = 44
    private var bottomTracking: NSTrackingArea?
    private var topTracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        [bottomTracking, topTracking].compactMap { $0 }.forEach { removeTrackingArea($0) }
        // Bottom-left origin: the bottom strip is y 0..h; the top strip is the top of the view.
        let bh = min(bottomZoneHeight, bounds.height)
        let bottom = NSTrackingArea(
            rect: NSRect(x: 0, y: 0, width: bounds.width, height: bh),
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: self, userInfo: ["zone": "bottom"]
        )
        addTrackingArea(bottom); bottomTracking = bottom
        let th = min(topZoneHeight, bounds.height)
        let top = NSTrackingArea(
            rect: NSRect(x: 0, y: bounds.height - th, width: bounds.width, height: th),
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: self, userInfo: ["zone": "top"]
        )
        addTrackingArea(top); topTracking = top
    }

    override func mouseEntered(with event: NSEvent) {
        if let z = event.trackingArea?.userInfo?["zone"] as? String { notify(z, true) }
    }
    override func mouseExited(with event: NSEvent) {
        if let z = event.trackingArea?.userInfo?["zone"] as? String { notify(z, false) }
    }
    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        notify("bottom", p.y <= bottomZoneHeight)
        notify("top", p.y >= bounds.height - topZoneHeight)
    }
    private func notify(_ zone: String, _ inside: Bool) {
        if zone == "top" { onHoverTop?(inside) } else { onHoverBottom?(inside) }
    }
}

/// NSTextView that reports the 2-finger horizontal drag as a continuous pan, so that
/// note navigation follows the finger (Antinote style) instead of jumping abruptly.
final class EditorTextView: NSTextView {
    /// (accumulated X offset of the gesture, true when the gesture ended).
    var onPan: ((CGFloat, Bool) -> Void)?
    private var accumX: CGFloat = 0
    private var panning = false

    override func scrollWheel(with event: NSEvent) {
        // A regular mouse (no precise deltas) follows the normal scroll.
        guard event.hasPreciseScrollingDeltas else { super.scrollWheel(with: event); return }

        // Ignore the post-release momentum, so it does not keep navigating on its own.
        if event.momentumPhase != [] {
            if panning { panning = false; accumX = 0 }
            return
        }

        switch event.phase {
        case .began:
            accumX = 0; panning = false
        case .ended, .cancelled:
            if panning { onPan?(accumX, true) }
            accumX = 0; panning = false
            return
        default:
            break
        }

        let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
        if !panning && abs(dx) <= abs(dy) * 1.4 {
            super.scrollWheel(with: event)  // vertical gesture: normal text scroll
            return
        }
        panning = true
        accumX += dx
        onPan?(accumX, false)
    }
}

/// Main editor: navigable deck of notes (Antinote style), autosave to SQLite,
/// command palette (⌘K / `::`) and rendered preview (markdown/json/code).
final class EditorViewController: NSViewController {
    private let registry: CommandRegistry
    private let database: Database?

    private var notes: [Note] = []
    private var index: Int = 0
    private var currentNote: Note {
        get { notes.indices.contains(index) ? notes[index] : Note() }
        set { if notes.indices.contains(index) { notes[index] = newValue } }
    }

    // UI
    private let textView = EditorTextView()
    private let scrollView = NSScrollView()
    /// The preview renders static, app-generated HTML, so JavaScript stays OFF.
    /// This neutralises any script injected through note content (e.g. a markdown
    /// link with a javascript: URL or an onerror handler).
    private let webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        return WKWebView(frame: .zero, configuration: config)
    }()
    /// Liquid Glass backing: NSGlassEffectView on macOS 26, NSVisualEffectView fallback.
    private let glassBacking = GlassBackground.backing()
    /// Theme color layer over the glass (alpha = opacity). Stays FIXED in the back:
    /// the text slides over it, so the transparency is uniform and constant,
    /// not just during the slide between notes. TintView (not a plain NSView) so the color
    /// survives the theme switch: see TintView.swift.
    private let tintView = TintView()
    private var footerStack: NSView?
    private var footerSolidTint: TintView?
    private var theme: Theme = Theme.byID(Settings.themeID)
    private let accessibility = AccessibilityMonitor()
    private var chromeRevealed = false
    private var buttonsRevealed = false
    private let footerHeight: CGFloat = 36
    /// Welcome cheatsheet still untouched: do not persist until the user edits it.
    private var welcomeIsUnsaved = false
    /// True when the last change was typing a single ":" (not paste/programmatic).
    private var lastTypedSingleColon = false
    /// Swipe already committed to the full transition (Antinote style, decisive).
    private var panCommitted = false
    private let dateLabel = NSTextField(labelWithString: "")
    private var searchPanel: KeyablePanel?
    /// Search panel (⌘F) open: the AppDelegate does not apply hide-on-blur.
    var isSearchOpen: Bool { searchPanel != nil }

    private static let footerDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "d MMM yyyy"
        return f
    }()
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "en_US")
        f.unitsStyle = .full
        return f
    }()
    private let languagePopup = NSPopUpButton()
    private let hintLabel = NSTextField(labelWithString: "")
    private let counterLabel = NSTextField(labelWithString: "")
    private let prevButton = NSButton()
    private let nextButton = NSButton()
    private let newButton = NSButton()
    private let previewButton = NSButton()
    private let pinButton = NSButton()
    private let settingsButton = NSButton()

    private var isPreviewing = false
    private var saveWorkItem: DispatchWorkItem?
    private var palettePanel: KeyablePanel?

    /// The AppDelegate checks this to avoid applying hide-on-blur with the palette open.
    var isPaletteOpen: Bool { palettePanel != nil }
    /// Pinned panel: does not disappear on losing focus. Checked by the AppDelegate.
    private(set) var isPinned = false

    private static let languages = [
        "auto", "markdown", "text", "json", "swift", "typescript", "javascript",
        "python", "go", "rust", "shell", "sql", "html", "yaml",
    ]

    init(registry: CommandRegistry, database: Database?) {
        self.registry = registry
        self.database = database
        // Load all notes (most recent first), or a cheatsheet on the first launch.
        let loaded = (try? database?.recentNotes(limit: 500)) ?? []
        self.notes = loaded.isEmpty ? [Note(content: Self.welcomeText, languageId: "markdown")] : loaded
        self.index = 0
        super.init(nibName: nil, bundle: nil)
        self.welcomeIsUnsaved = loaded.isEmpty
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    deinit { NotificationCenter.default.removeObserver(self) }

    private static let welcomeText = """
    # ScratchMate

    A programmable scratchpad for your code.

    Press ⌘K (or type ::) to open the commands:

      ::date       insert an ISO 8601 timestamp
      ::uuid       generate a UUID
      ::json       pretty-print JSON
      ::sort       sort the lines
      ::dedupe     remove duplicate lines
      ::case       toggle upper/lower case
      ::comment    comment the lines (by language)
      ::wrap       wrap the selection in `code`
      ::codeblock  copy as a markdown block
      ::export     export the note as .md

    Swipe sideways (or ⌘[ / ⌘]) to switch notes. ⌘N starts a new one.
    ⌘R toggles the preview. Everything stays local in SQLite. Global hotkey: Cmd-Shift-Space.

    Press ⌘, for themes, shortcuts and more.
    """

    private static let previewDemo = """
    # ScratchMate

    Live **markdown** rendering, with *emphasis*, `inline code` and links like [Antinote](https://antinote.io).

    ## Commands
    - `::json` formats JSON
    - `::sort` sorts the lines
    - `::export` saves as .md

    > A workbench for text and code, not a notebook.

    ```swift
    let note = Note(content: "hello world")
    ```
    """

    // MARK: - Layout

    override func loadView() {
        let container = HoverView(frame: NSRect(x: 0, y: 0, width: 720, height: 460))
        container.wantsLayer = true
        container.onHoverBottom = { [weak self] inside in self?.revealChrome(inside) }
        container.onHoverTop = { [weak self] inside in self?.revealWindowButtons(inside) }
        // Clip the content (glass, editor, footer) to the window's rounded corners.
        container.layer?.cornerRadius = 12
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true

        // Liquid Glass backing (real glass on macOS 26, blur fallback below).
        glassBacking.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(glassBacking)

        // Theme color layer over the glass (fixed, does not slide). It is what provides the
        // uniform transparency; the editor on top of it is transparent.
        tintView.wantsLayer = true
        tintView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tintView)

        // Editor fills the whole area.
        textView.delegate = self
        textView.onPan = { [weak self] accumX, ended in
            self?.handlePan(accumX, ended: ended)
        }
        applyEditorFont()  // family + size from Settings (defaults to SF Mono 13)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.drawsBackground = false  // transparent: the color comes from the fixed tintView behind
        textView.textContainerInset = NSSize(width: 12, height: 16)

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.contentView.drawsBackground = false  // the clipView must not cover the glass
        scrollView.wantsLayer = true
        scrollView.automaticallyAdjustsContentInsets = false
        // Top margin so the text never sits under the window traffic lights (which
        // reveal on hover in the top strip). Keeps the first line clear of the chrome.
        scrollView.contentInsets.top = 24
        container.addSubview(scrollView)

        // Preview fills the same area.
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.isHidden = true
        webView.setValue(false, forKey: "drawsBackground")
        container.addSubview(webView)

        // Chrome: floating bar at the bottom, hidden until hover.
        let footer = buildFooter()
        self.footerStack = footer
        container.addSubview(footer)

        NSLayoutConstraint.activate([
            glassBacking.topAnchor.constraint(equalTo: container.topAnchor),
            glassBacking.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            glassBacking.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            glassBacking.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            tintView.topAnchor.constraint(equalTo: container.topAnchor),
            tintView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tintView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            footer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: footerHeight),
        ])

        self.view = container
        applyTheme()
        applyOpacity()
        chromeRevealed = Settings.alwaysShowChrome
        footer.alphaValue = chromeRevealed ? 1 : 0
        scrollView.contentInsets.bottom = chromeRevealed ? footerHeight : 0
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged),
            name: .scratchMateSettingsChanged, object: nil
        )
        // Live opacity drag: reapply translucency only, no full theme/font rebuild.
        NotificationCenter.default.addObserver(
            self, selector: #selector(opacityPreview),
            name: .scratchMateOpacityPreview, object: nil
        )
        // Follow the system Light/Dark switch when "follow system" is on.
        DistributedNotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil
        )
        // React live to Reduce Transparency / Reduce Motion / Increase Contrast.
        accessibility.onChange = { [weak self] in self?.applyTheme() }
        loadCurrentIntoView()
    }

    private func buildFooter() -> NSView {
        configureIconButton(prevButton, symbol: "chevron.left", tip: "Older note (⌘[)", action: #selector(goOlder))
        configureIconButton(newButton, symbol: "plus", tip: "New note (⌘N)", action: #selector(newNoteAction))
        configureIconButton(nextButton, symbol: "chevron.right", tip: "Newer note (⌘])", action: #selector(goNewer))
        configureIconButton(previewButton, symbol: "eye", tip: "Preview (⌘R)", action: #selector(togglePreview))
        configureIconButton(pinButton, symbol: "pin", tip: "Pin to screen (⌘P)", action: #selector(togglePin))
        configureIconButton(settingsButton, symbol: "gearshape", tip: "Settings (⌘,)", action: #selector(openSettings))

        counterLabel.font = .monospacedDigitSystemFont(ofSize: Typography.caption().pointSize, weight: .medium)
        dateLabel.font = Typography.caption()
        languagePopup.addItems(withTitles: Self.languages)
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged)
        languagePopup.bezelStyle = .inline
        languagePopup.controlSize = .small

        hintLabel.font = Typography.caption()
        hintLabel.lineBreakMode = .byTruncatingTail

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [
            prevButton, newButton, nextButton, counterLabel, dateLabel, hintLabel, spacer,
            languagePopup, pinButton, previewButton, settingsButton,
        ])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Chrome bar in glass (real glass on macOS 26, header material below), so
        // the footer speaks the same glass language as the editor backing.
        let bar = GlassBackground.chromeBar()
        bar.translatesAutoresizingMaskIntoConstraints = false

        // Solid-bars option: an opaque tint behind the chrome, toggled in applyOpacity.
        let solid = TintView()
        solid.fillColor = .clear
        solid.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(solid)
        self.footerSolidTint = solid

        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            solid.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            solid.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            solid.topAnchor.constraint(equalTo: bar.topAnchor),
            solid.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            stack.topAnchor.constraint(equalTo: bar.topAnchor),
            stack.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
        ])
        return bar
    }

    private func configureIconButton(_ button: NSButton, symbol: String, tip: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        button.symbolConfiguration = .preferringHierarchical()  // depth on the chrome glyphs
        button.bezelStyle = .accessoryBar
        button.isBordered = false
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = tip
        button.target = self
        button.action = action
        button.setButtonType(.momentaryChange)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
        // Traffic lights start hidden; they appear on hover of the top strip.
        if !Settings.alwaysShowChrome {
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                view.window?.standardWindowButton(type)?.alphaValue = 0
            }
        }
    }

    // MARK: - Theme, transparency and chrome

    /// Live accent: system control accent, the Caret amber, or a custom color, per
    /// Settings.accentSource. This is what the chrome highlights use.
    private func currentAccent() -> NSColor {
        switch Settings.accentSource {
        case "system": return .controlAccentColor
        case "custom": return NSColor(hex: Settings.customAccentHex)
        default: return DesignTokens.accent
        }
    }

    /// Applies the active theme to the editor, the chrome and (if open) the preview.
    /// The theme id in effect, honoring "follow system appearance".
    private func resolvedThemeID() -> String {
        guard Settings.themeFollowsSystem else { return Settings.themeID }
        let systemDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        return systemDark ? Settings.darkThemeID : Settings.lightThemeID
    }

    private func applyTheme() {
        theme = Theme.byID(resolvedThemeID())
        view.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
        glassBacking.appearance = view.appearance
        let accent = currentAccent()

        textView.textColor = theme.foregroundColor
        textView.insertionPointColor = accent
        textView.selectedTextAttributes = [.backgroundColor: accent.withAlphaComponent(0.32)]

        counterLabel.textColor = theme.secondaryColor
        dateLabel.textColor = theme.secondaryColor
        hintLabel.textColor = theme.secondaryColor
        for b in [prevButton, nextButton, newButton, previewButton, settingsButton] {
            b.contentTintColor = theme.secondaryColor
        }
        pinButton.contentTintColor = isPinned ? accent : theme.secondaryColor
        footerStack?.appearance = view.appearance

        applyOpacity()
        // Setting view.appearance makes AppKit rebuild the tintView backing layer on the
        // next runloop pass, which can drop the freshly set color. Reapply the tint after
        // that rebuild and force a redraw so the transparency survives the theme switch
        // (including the dark<->light crossover).
        view.needsDisplay = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyOpacity()
            self.view.needsDisplay = true
        }
    }

    /// Applies the transparency by tinting the FIXED background layer (not the editor). This way the
    /// glass appears uniform the whole time, not just when the content slides during the slide.
    private func applyOpacity() {
        // Translucency off (or Reduce Transparency on) means a fully opaque surface.
        let translucent = Settings.translucencyEnabled && !accessibility.reduceTransparency
        var o: CGFloat = translucent ? CGFloat(Settings.opacity) : 1.0
        // Increase Contrast nudges the surface toward opaque for legibility.
        if accessibility.increaseContrast { o = max(o, 0.92) }
        tintView.fillColor = theme.backgroundColor.withAlphaComponent(o)
        // Solid bars: opaque chrome over the translucent body when the user asks.
        let wantSolidBars = translucent && (Settings.solidBarsInTranslucency || accessibility.increaseContrast)
        footerSolidTint?.fillColor = wantSolidBars ? theme.backgroundColor : .clear
        if isPreviewing { refreshPreview() }
    }

    /// Applies the configured editor font (family + size), falling back to SF Mono.
    private func applyEditorFont() {
        let size = CGFloat(Settings.editorFontSize) * (Settings.doubleTextSize ? 2 : 1)
        let family = Settings.editorFontFamily
        if family.isEmpty {
            textView.font = .monospacedSystemFont(ofSize: size, weight: .regular)
        } else {
            textView.font = NSFont(name: family, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }

    /// Reveals or hides the chrome with a fade. Keeps it lit with the palette open or
    /// "always show". Idempotent: mouseMoved fires a lot, only acts if it changes.
    private func revealChrome(_ inside: Bool) {
        let want = inside || Settings.alwaysShowChrome || isPaletteOpen
        if want == chromeRevealed { return }
        chromeRevealed = want
        scrollView.contentInsets.bottom = want ? footerHeight : 0
        guard let footer = footerStack else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            footer.animator().alphaValue = want ? 1 : 0
        }
    }

    /// Reveals/hides the window buttons (close/min/zoom) on hover of the top strip.
    private func revealWindowButtons(_ inside: Bool) {
        let want = inside || Settings.alwaysShowChrome
        if want == buttonsRevealed { return }
        buttonsRevealed = want
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let b = view.window?.standardWindowButton(type) else { continue }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                b.animator().alphaValue = want ? 1 : 0
            }
        }
    }

    /// Live opacity drag: just the translucency, no theme/font rebuild.
    @objc private func opacityPreview() {
        applyOpacity()
    }

    @objc private func settingsChanged() {
        applyTheme()
        applyEditorFont()
        counterLabel.isHidden = !Settings.showNoteCount
        if Settings.alwaysShowChrome {
            chromeRevealed = true
            footerStack?.alphaValue = 1
            scrollView.contentInsets.bottom = footerHeight
        } else if !chromeRevealed {
            footerStack?.alphaValue = 0
            scrollView.contentInsets.bottom = 0
        }
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    // MARK: - Visual capture (snapshot mode, no Screen Recording)

    /// Renders the editor window to PNG via cacheDisplay and quits the app.
    func snapshotEditor(to path: String) {
        footerStack?.alphaValue = 1  // reveal the chrome so it shows in the capture
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { NSApp.terminate(nil); return }
            self.view.layoutSubtreeIfNeeded()
            let bounds = self.view.bounds
            if let rep = self.view.bitmapImageRepForCachingDisplay(in: bounds) {
                self.view.cacheDisplay(in: bounds, to: rep)
                if let data = rep.representation(using: .png, properties: [:]) {
                    try? data.write(to: URL(fileURLWithPath: path))
                }
            }
            NSApp.terminate(nil)
        }
    }

    /// Turns on the preview and uses the WKWebView's takeSnapshot (cacheDisplay does not capture web).
    func snapshotPreview(to path: String) {
        textView.string = Self.previewDemo
        currentNote.languageId = "markdown"
        if !isPreviewing { togglePreview() } else { refreshPreview() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { NSApp.terminate(nil); return }
            let config = WKSnapshotConfiguration()
            self.webView.takeSnapshot(with: config) { image, _ in
                if let image, let tiff = image.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path))
                }
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - Load / save the current note

    private func loadCurrentIntoView() {
        textView.string = currentNote.content
        languagePopup.selectItem(withTitle: currentNote.languageId)
        counterLabel.stringValue = "\(index + 1)/\(notes.count)"
        counterLabel.isHidden = !Settings.showNoteCount
        dateLabel.stringValue = Self.footerDateFormatter.string(from: currentNote.updatedAt)
        prevButton.isEnabled = index < notes.count - 1
        nextButton.isEnabled = true  // ⌘] at the top creates a new note, always enabled
        if isPreviewing { refreshPreview() }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveCurrentNow() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Persists the current note. Called on debounce, when navigating and when hiding the panel.
    func saveCurrentNow() {
        saveWorkItem?.cancel()  // discard the pending debounce so it does not stamp updated_at later
        saveWorkItem = nil
        guard notes.indices.contains(index) else { return }
        var n = notes[index]
        n.content = textView.string
        // Do not persist the initial cheatsheet while the user has not edited it.
        if n.id == 0 && welcomeIsUnsaved && n.content == Self.welcomeText { return }
        n.title = Note.derivedTitle(from: n.content)
        n.updatedAt = Date()
        n.expiresAt = computeExpiry(from: n.updatedAt)
        if let database {
            do {
                if n.id == 0 { n = try database.insert(n) } else { try database.update(n) }
                notes[index] = n
            } catch {
                NSLog("ScratchMate: failed to save note: \(error)")
                flashHint("Save failed")  // keep id=0 so the next save retries
            }
        } else {
            notes[index] = n
        }
    }

    /// Expiry date from the preferences (counted from the last edit). nil = "Never".
    private func computeExpiry(from date: Date) -> Date? {
        let days = Settings.autoExpireDays
        guard days > 0 else { return nil }
        return Calendar.current.date(byAdding: .day, value: days, to: date)
    }

    // MARK: - Navigation between notes (Antinote style)

    @objc private func goOlder() { navigate(toNewer: false, animated: true) }
    @objc private func goNewer() { navigate(toNewer: true, animated: true) }
    @objc private func newNoteAction() { newNote() }

    @objc private func togglePin() {
        isPinned.toggle()
        pinButton.image = NSImage(
            systemSymbolName: isPinned ? "pin.fill" : "pin",
            accessibilityDescription: isPinned ? "Unpin" : "Pin"
        )
        pinButton.contentTintColor = isPinned ? currentAccent() : theme.secondaryColor
        view.window?.level = isPinned ? .statusBar : .floating
        flashHint(isPinned ? "Pinned to screen" : "Unpinned")
    }

    /// toNewer=true goes to the more recent note; going past the top creates a new note.
    /// toNewer=false goes to the older one.
    private func navigate(toNewer: Bool, animated: Bool) {
        saveCurrentNow()
        if toNewer {
            if index == 0 {
                if currentNote.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    view.window?.makeFirstResponder(textView)
                    flashHint("Already on a blank note")
                    return
                }
                newNote(); return
            }
        } else if index >= notes.count - 1 {
            return  // already on the oldest
        }

        let leaving = index
        index = toNewer ? index - 1 : index + 1
        discardIfEmpty(at: leaving)
        if animated { animateSlide(toNewer: toNewer) }
        loadCurrentIntoView()
        view.window?.makeFirstResponder(textView)
    }

    /// Creates an empty note and navigates to it. Reuses an empty note that is already current.
    func newNote() {
        saveCurrentNow()
        if currentNote.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            view.window?.makeFirstResponder(textView)
            return  // a blank note is already open, do not stack another
        }
        var note = Note(content: "", languageId: Settings.defaultNoteLanguage)
        note.expiresAt = computeExpiry(from: note.updatedAt)
        if let database {
            do { note = try database.insert(note) }
            catch { NSLog("ScratchMate: failed to create note: \(error)"); flashHint("Failed to create note") }
        }
        notes.insert(note, at: 0)
        index = 0
        animateSlide(toNewer: true, isNew: true)
        loadCurrentIntoView()
        view.window?.makeFirstResponder(textView)
        if Settings.defaultPinned && !isPinned { togglePin() }  // new notes start pinned if set
        showToast("New note")
    }

    /// Removes an empty note that was left behind (keeps at least one live note).
    private func discardIfEmpty(at idx: Int) {
        guard notes.indices.contains(idx), notes.count > 1 else { return }
        let n = notes[idx]
        guard n.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if n.id != 0 { try? database?.delete(id: n.id) }
        notes.remove(at: idx)
        if idx < index { index -= 1 }
        index = min(max(index, 0), notes.count - 1)
    }

    @objc private func deleteCurrentNote() {
        if notes.count <= 1 {
            textView.string = ""
            saveCurrentNow()
            return
        }
        let n = notes[index]
        if n.id != 0 { try? database?.delete(id: n.id) }
        notes.remove(at: index)
        index = min(index, notes.count - 1)
        animateSlide(toNewer: false)
        loadCurrentIntoView()
    }

    /// Carousel transition between notes. A new note enters on top (moveIn) with a
    /// slightly longer duration, navigation uses push, both with smooth easing.
    private func animateSlide(toNewer: Bool, isNew: Bool = false) {
        if accessibility.reduceMotion { return }  // honor Reduce Motion: swap with no slide
        let t = CATransition()
        t.type = isNew ? .moveIn : .push
        t.subtype = toNewer ? .fromRight : .fromLeft
        t.duration = isNew ? 0.34 : 0.26
        t.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        scrollView.layer?.add(t, forKey: "slide")
        webView.layer?.add(t, forKey: "slide")
    }

    /// Decisive swipe Antinote style: the content follows the finger only up to the cue; as
    /// soon as the gesture is confirmed, it fires the FULL transition (creates a note or walks
    /// through the notes) and ignores the rest. Direction: to the right = older note; to the left =
    /// newer (or creates, at the top).
    private func handlePan(_ accumX: CGFloat, ended: Bool) {
        if ended {
            if !panCommitted {
                let tx = accumX * 0.5
                setContentTranslation(0)
                if abs(tx) > 0.5 { animateReturn(from: tx) }
            }
            panCommitted = false
            return
        }
        if panCommitted { return }
        revealChrome(false)
        if abs(accumX) > 26 {  // cue confirmed: runs the whole animation
            panCommitted = true
            setContentTranslation(0)
            navigate(toNewer: accumX < 0, animated: true)
        } else {
            setContentTranslation(accumX * 0.5)  // follows the finger up to the cue
        }
    }

    /// Moves the content (editor + preview) in X with no implicit animation (follows the finger).
    private func setContentTranslation(_ x: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let t = CGAffineTransform(translationX: x, y: 0)
        scrollView.layer?.setAffineTransform(t)
        webView.layer?.setAffineTransform(t)
        CATransaction.commit()
    }

    /// When the gesture does not pass the threshold, animates the content back into place.
    private func animateReturn(from tx: CGFloat) {
        for layer in [scrollView.layer, webView.layer].compactMap({ $0 }) {
            let anim = CABasicAnimation(keyPath: "transform.translation.x")
            anim.fromValue = tx
            anim.toValue = 0
            anim.duration = 0.28
            anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(anim, forKey: "return")
        }
    }

    // MARK: - Rendered preview

    @objc private func togglePreview() {
        isPreviewing.toggle()
        webView.isHidden = !isPreviewing
        scrollView.isHidden = isPreviewing
        previewButton.image = NSImage(
            systemSymbolName: isPreviewing ? "pencil" : "eye",
            accessibilityDescription: isPreviewing ? "Edit" : "Preview"
        )
        if isPreviewing {
            refreshPreview()
        } else {
            view.window?.makeFirstResponder(textView)
        }
    }

    private func refreshPreview() {
        webView.loadHTMLString(previewHTML(), baseURL: nil)
    }

    /// A command that writes to the buffer while the preview is open: switches back to the editor
    /// so the user sees the change (otherwise the edit happens in a hidden view).
    private func exitPreviewIfNeeded() {
        if isPreviewing { togglePreview() }
    }

    /// Render by format: markdown becomes HTML; json is formatted; code becomes a block.
    private func previewHTML() -> String {
        let content = textView.string
        let pal = theme.markdownPalette
        switch effectiveLanguageId(for: content) {
        case "markdown", "text":
            return MarkdownRenderer.htmlDocument(content, palette: pal)
        case "json":
            let pretty = NativeCommands.formatJSON.run(content, CommandContext())
            return MarkdownRenderer.htmlDocument("```json\n\(pretty)\n```", palette: pal)
        case let lang:
            return MarkdownRenderer.htmlDocument("```\(lang)\n\(content)\n```", palette: pal)
        }
    }

    /// Resolves "auto" to a language guessed from the content; otherwise returns
    /// the note's explicit language id.
    private func effectiveLanguageId(for content: String) -> String {
        currentNote.languageId == "auto" ? LanguageDetector.detect(content) : currentNote.languageId
    }

    // MARK: - Language

    @objc private func languageChanged() {
        currentNote.languageId = languagePopup.titleOfSelectedItem ?? "markdown"
        scheduleSave()
        if isPreviewing { refreshPreview() }
    }

    // MARK: - Command palette

    func openPalette(initialQuery: String = "") {
        guard palettePanel == nil, let window = view.window else { return }

        let paletteVC = CommandPaletteController(registry: registry)
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.contentViewController = paletteVC
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true

        paletteVC.onExecute = { [weak self] command in
            self?.dismissPalette()
            self?.execute(command)
        }
        paletteVC.onCancel = { [weak self] in self?.dismissPalette() }

        let pFrame = panel.frame
        let wFrame = window.frame
        panel.setFrameOrigin(NSPoint(x: wFrame.midX - pFrame.width / 2, y: wFrame.midY - pFrame.height / 2))

        self.palettePanel = panel
        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        paletteVC.prepare(languageId: currentNote.languageId, initialQuery: initialQuery)
        paletteVC.focusSearch()
    }

    private func dismissPalette() {
        guard let panel = palettePanel else { return }
        view.window?.removeChildWindow(panel)
        panel.orderOut(nil)
        palettePanel = nil
        view.window?.makeKeyAndOrderFront(nil)
        view.window?.makeFirstResponder(textView)
        revealChrome(false)  // palette closed: hide the chrome if the mouse is not inside
    }

    // MARK: - Find across all notes (⌘F)

    @objc func openSearchAction() { openSearch() }

    func openSearch() {
        guard searchPanel == nil, let window = view.window else { return }
        let sc = SearchController(database: database, theme: theme)
        let panel = KeyablePanel(
            contentRect: window.frame,
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.contentViewController = sc
        sc.onPick = { [weak self] note in self?.dismissSearch(); self?.openNote(note) }
        sc.onCancel = { [weak self] in self?.dismissSearch() }
        panel.setFrame(window.frame, display: true)
        searchPanel = panel
        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        sc.focusSearch()
    }

    private func dismissSearch() {
        guard let panel = searchPanel else { return }
        view.window?.removeChildWindow(panel)
        panel.orderOut(nil)
        searchPanel = nil
        view.window?.makeKeyAndOrderFront(nil)
        view.window?.makeFirstResponder(textView)
    }

    /// Opens a note picked from search: finds it in the loaded deck or reloads from the database.
    private func openNote(_ note: Note) {
        saveCurrentNow()
        if let i = notes.firstIndex(where: { $0.id == note.id }) {
            index = i
        } else {
            notes = (try? database?.recentNotes(limit: 500)) ?? notes
            index = notes.firstIndex(where: { $0.id == note.id }) ?? 0
        }
        loadCurrentIntoView()
        view.window?.makeFirstResponder(textView)
    }

    // MARK: - Command execution

    private func buildContext() -> CommandContext {
        let full = textView.string as NSString
        let selRange = textView.selectedRange()
        let selectedText = selRange.length > 0 ? full.substring(with: selRange) : ""
        let lineRange = full.lineRange(for: NSRange(location: min(selRange.location, full.length), length: 0))
        let currentLine = full.substring(with: lineRange).trimmingCharacters(in: .newlines)

        return CommandContext(
            selectedText: selectedText,
            currentLine: currentLine,
            currentWord: "",
            languageId: currentNote.languageId,
            noteContent: textView.string,
            noteTitle: currentNote.title,
            now: Date()
        )
    }

    func execute(_ command: TextCommand) {
        let ctx = buildContext()
        let full = textView.string as NSString
        let selRange = textView.selectedRange()
        let hasSelection = selRange.length > 0

        let inputText: String
        switch command.input {
        case .document: inputText = textView.string
        case .selection: inputText = hasSelection ? full.substring(with: selRange) : textView.string
        case .none: inputText = ""
        }

        let output = command.run(inputText, ctx)

        switch command.output {
        case .replaceDocument:
            exitPreviewIfNeeded()
            replace(range: NSRange(location: 0, length: full.length), with: output)
        case .replaceSelection:
            exitPreviewIfNeeded()
            replace(range: hasSelection ? selRange : NSRange(location: 0, length: full.length), with: output)
        case .insert:
            exitPreviewIfNeeded()
            replace(range: selRange, with: output)
        case .clipboard:
            copyToClipboard(output); flashHint("Copied to clipboard")
        case .newNote:
            createNote(content: output)
        case .file:
            exportToFile(content: output)
        }
    }

    private func replace(range: NSRange, with string: String) {
        guard textView.shouldChangeText(in: range, replacementString: string) else { return }
        textView.replaceCharacters(in: range, with: string)
        textView.didChangeText()
        scheduleSave()
    }

    private func copyToClipboard(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }

    private func createNote(content: String) {
        saveCurrentNow()  // flush the current note before stacking the new one (avoids edit loss)
        var note = Note(title: Note.derivedTitle(from: content), content: content, languageId: currentNote.languageId)
        note.expiresAt = computeExpiry(from: note.updatedAt)
        if let database {
            do { note = try database.insert(note) }
            catch { NSLog("ScratchMate: failed to create note: \(error)"); flashHint("Failed to create note") }
        }
        notes.insert(note, at: 0)
        index = 0
        animateSlide(toNewer: true, isNew: true)
        loadCurrentIntoView()
        showToast("New note created")
    }

    private func exportToFile(content: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(Note.derivedTitle(from: content, max: 30)).md"
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                flashHint("Exported to \(url.lastPathComponent)")
            } catch {
                flashHint("Export failed")
            }
        }
    }

    private func flashHint(_ message: String) {
        hintLabel.stringValue = message
        hintLabel.textColor = currentAccent()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            self?.hintLabel.stringValue = ""
            self?.hintLabel.textColor = self?.theme.secondaryColor
        }
    }

    /// Soft toast centered at the top of the editor, visible even with the chrome hidden.
    private func showToast(_ message: String) {
        let toast = NSTextField(labelWithString: message)
        toast.font = Typography.caption()
        toast.textColor = theme.foregroundColor
        toast.alignment = .center
        toast.drawsBackground = false
        toast.translatesAutoresizingMaskIntoConstraints = false

        let pill = NSView()
        pill.wantsLayer = true
        pill.layer?.backgroundColor = theme.backgroundColor.withAlphaComponent(0.92).cgColor
        pill.layer?.cornerRadius = 9
        pill.layer?.cornerCurve = .continuous
        pill.layer?.borderWidth = 1
        pill.layer?.borderColor = currentAccent().withAlphaComponent(0.4).cgColor
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(toast)
        view.addSubview(pill)

        NSLayoutConstraint.activate([
            toast.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 14),
            toast.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -14),
            toast.topAnchor.constraint(equalTo: pill.topAnchor, constant: 7),
            toast.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -7),
            pill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pill.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
        ])

        pill.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            pill.animator().alphaValue = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                pill.animator().alphaValue = 0
            }, completionHandler: { MainActor.assumeIsolated { pill.removeFromSuperview() } })
        }
    }

    // MARK: - `::` trigger

    /// Opens the palette only when the user JUST typed the second `:` (not paste,
    /// not a programmatic edit) AND the `::` is at the start of a line or after a space. This way
    /// `std::`, `Foo::bar`, `Vec::new` in a code scratchpad do not trigger the palette.
    private func handleDoubleColonTrigger() {
        guard lastTypedSingleColon else { return }
        lastTypedSingleColon = false
        let full = textView.string as NSString
        let caret = textView.selectedRange().location
        guard caret >= 2 else { return }
        guard full.substring(with: NSRange(location: caret - 2, length: 2)) == "::" else { return }
        if caret >= 3 {
            let prev = full.substring(with: NSRange(location: caret - 3, length: 1))
            guard prev == "\n" || prev == " " || prev == "\t" else { return }
        }
        let removeRange = NSRange(location: caret - 2, length: 2)
        if textView.shouldChangeText(in: removeRange, replacementString: "") {
            textView.replaceCharacters(in: removeRange, with: "")
            textView.didChangeText()
        }
        openPalette()
    }
}

extension EditorViewController: NSTextViewDelegate {
    nonisolated func textView(
        _ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
        replacementString: String?
    ) -> Bool {
        MainActor.assumeIsolated {
            // Only counts as a trigger if it was typing a single ":" (not paste).
            lastTypedSingleColon = (replacementString == ":" && affectedCharRange.length == 0)
        }
        return true
    }

    nonisolated func textDidChange(_ notification: Notification) {
        MainActor.assumeIsolated {
            if welcomeIsUnsaved && textView.string != Self.welcomeText { welcomeIsUnsaved = false }
            revealChrome(false)  // typed: hide the controls (they reappear on hover at the corner)
            handleDoubleColonTrigger()
            scheduleSave()
        }
    }

    /// Antinote-style auto-copy: when enabled, the live selection is mirrored to
    /// the clipboard so a quick highlight is enough to grab a snippet.
    nonisolated func textViewDidChangeSelection(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard Settings.autoCopyOnSelect else { return }
            let sel = textView.selectedRange()
            guard sel.length > 0,
                  let text = textView.string as NSString?,
                  sel.location + sel.length <= text.length else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text.substring(with: sel), forType: .string)
        }
    }
}
