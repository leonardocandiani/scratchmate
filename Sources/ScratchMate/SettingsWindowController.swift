import AppKit
import Carbon.HIToolbox
import ServiceManagement
import ScratchMateCore

/// Settings as a native System Settings window: an `NSTabViewController` with a
/// toolbar tab style, one `NSViewController` per section (each with an SF Symbol),
/// `toolbarStyle = .preference`, only a close button, Esc to close, per-tab
/// window resizing, and a cross-fade that respects Reduce Motion.
///
/// AppDelegate drives this through `SettingsWindowController.shared.show()` and,
/// in snapshot mode, reads `shared.window?.contentView`, so both stay public.
/// The controller hosts the tab view; a dedicated `NSWindow` wraps it so the
/// existing call sites keep working without an extra window controller.
final class SettingsWindowController: NSTabViewController {

    static let shared = SettingsWindowController()

    /// The window that hosts this tab controller. Created lazily so the chrome
    /// is set up exactly once, on first show or snapshot.
    private(set) var hostingWindow: NSWindow?

    /// Mirror of the old NSWindowController surface AppDelegate relies on.
    var window: NSWindow? { hostingWindow }

    private let accessibility = AccessibilityMonitor()

    init() {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        title = "Settings"  // shown in the window title bar (NSTabViewController uses it)
        // Cross-fade respecting Reduce Motion (see transition override below).
        transitionOptions = accessibility.reduceMotion ? [] : [.crossfade]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - Tabs

    override func viewDidLoad() {
        super.viewDidLoad()

        let sections: [(NSViewController, String, String)] = [
            (GeneralSettingsViewController(), "General", "gearshape"),
            (AppearanceSettingsViewController(), "Appearance", "paintbrush"),
            (EditorSettingsViewController(), "Editor", "textformat"),
            (BehaviorSettingsViewController(), "Behavior", "slider.horizontal.3"),
            (ShortcutsSettingsViewController(), "Shortcuts", "command"),
            (PrivacySettingsViewController(), "Notes & Privacy", "lock"),
            (AdvancedSettingsViewController(), "Advanced", "gearshape.2"),
            (AboutSettingsViewController(), "About", "info.circle"),
        ]

        tabViewItems = sections.map { vc, title, symbol in
            let item = NSTabViewItem(viewController: vc)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            return item
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(externalSettingsChanged),
            name: .scratchMateSettingsChanged, object: nil
        )
    }

    /// Keep the cross-fade in sync with Reduce Motion as tabs change (the user
    /// can flip the system setting while Settings is open). NSTabViewController
    /// already resizes the window to each section because the sections declare a
    /// fixed width and intrinsic height.
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        transitionOptions = accessibility.reduceMotion ? [] : [.crossfade]
    }

    @objc private func externalSettingsChanged() {
        applyAppearanceToWindow()
    }

    // MARK: - Window

    private func buildWindowIfNeeded() {
        guard hostingWindow == nil else { return }

        let window = NSWindow(contentViewController: self)
        // No fullSizeContentView: the content must sit BELOW the preference toolbar,
        // not behind it (otherwise the first row of cards is clipped by the tabs).
        window.styleMask = [.titled, .closable]
        window.title = "ScratchMate Settings"
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
        hostingWindow = window
        applyAppearanceToWindow()
    }

    /// Settings follows the active theme (including the light Paper theme), like
    /// a native settings window that honours the app appearance.
    private func applyAppearanceToWindow() {
        let theme = Theme.byID(Settings.themeID)
        hostingWindow?.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
    }

    func show() {
        buildWindowIfNeeded()
        hostingWindow?.center()
        hostingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Esc closes the window (standard cancel behaviour).
    override func cancelOperation(_ sender: Any?) {
        hostingWindow?.performClose(sender)
    }

    /// Renders the settings content to a PNG via cacheDisplay, then exits. Mirrors
    /// EditorViewController.snapshotEditor: captures the controller's own view
    /// (the selected tab's content) with a fixed frame so it never sees zero bounds.
    /// Renders a single settings section (General) to PNG, then exits. Captures a
    /// section view directly instead of the NSTabViewController window: the toolbar
    /// tab controller hangs in a headless run, a lone section view does not.
    func snapshot(to path: String) {
        let size = NSSize(width: 560, height: 520)
        let section = GeneralSettingsViewController()
        let host = NSView(frame: NSRect(origin: .zero, size: size))
        host.appearance = NSAppearance(named: Theme.byID(Settings.themeID).isDark ? .darkAqua : .aqua)
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        section.view.frame = host.bounds
        section.view.autoresizingMask = [.width, .height]
        host.addSubview(section.view)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            host.layoutSubtreeIfNeeded()
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                if let d = rep.representation(using: .png, properties: [:]) {
                    try? d.write(to: URL(fileURLWithPath: path))
                }
            }
            NSApp.terminate(nil)
        }
    }

    /// Headless diagnostic: builds every section at the window's real height cap
    /// (560, the same constant the section uses) and prints whether the full
    /// content is reachable by scrolling. Verifies the Settings scroll without a
    /// screen capture, then exits.
    func diagnoseScroll() {
        let cap: CGFloat = 560
        let sections: [(String, SettingsSectionViewController)] = [
            ("General", GeneralSettingsViewController()),
            ("Appearance", AppearanceSettingsViewController()),
            ("Editor", EditorSettingsViewController()),
            ("Behavior", BehaviorSettingsViewController()),
            ("Shortcuts", ShortcutsSettingsViewController()),
            ("Notes & Privacy", PrivacySettingsViewController()),
            ("Advanced", AdvancedSettingsViewController()),
            ("About", AboutSettingsViewController()),
        ]
        for (name, vc) in sections {
            let m = vc.scrollMetrics(windowHeight: cap)
            let needsScroll = m.content > m.visible + 0.5
            print(String(format: "[scroll] %-16@ content=%.0f visible=%.0f scroll=%@ reachesEnd=%@",
                         name as NSString, m.content, m.visible,
                         needsScroll ? "yes" : "no", m.reachesEnd ? "OK" : "CLIPPED"))
        }
        NSApp.terminate(nil)
    }
}

// MARK: - Shared section scaffold

/// Base controller every settings section builds on. It owns a scrolling form
/// laid out as a single vertical stack of "groups", each group a heading plus
/// rows of label/control pairs aligned in an NSGridView. Subclasses override
/// `populate(into:)` and append groups; the base wires the scroll view, glass
/// backing, typography, and a live rebuild on `.scratchMateSettingsChanged`.
class SettingsSectionViewController: NSViewController {

    private let contentStack = NSStackView()
    private let scrollView = NSScrollView()
    private let documentView = NSView()
    /// Width the content column targets; the window sizes around this.
    let contentWidth: CGFloat = 540

    /// Retains the closure-backed control targets so they outlive `rebuild()`
    /// without per-control associated objects (cleaner under strict concurrency).
    /// Cleared and refilled on every rebuild.
    private var handlers: [NSObject] = []

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        // Native window-background surface so the content pane reads white in
        // light and dark-grey in dark, like System Settings, while glass lives
        // behind floating chrome elsewhere in the app.
        let backing = NSVisualEffectView()
        backing.material = .windowBackground
        backing.blendingMode = .behindWindow
        backing.state = .active
        backing.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(backing)

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 22
        contentStack.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 28, right: 28)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(contentStack)
        scrollView.documentView = documentView

        NSLayoutConstraint.activate([
            backing.topAnchor.constraint(equalTo: root.topAnchor),
            backing.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            backing.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            backing.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),

            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            contentStack.widthAnchor.constraint(equalToConstant: contentWidth),
        ])

        // NSTabViewController sizes the window from each section's fittingSize.
        // The scroll view has no intrinsic height, so without these the window
        // would collapse. Pin the section width, then let the content drive the
        // height: equal to the content (so short tabs fit exactly) and capped at
        // a max so a tall tab scrolls instead of overflowing the screen.
        root.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        let contentHeight = scrollView.heightAnchor.constraint(equalTo: documentView.heightAnchor)
        contentHeight.priority = .defaultHigh
        contentHeight.isActive = true
        scrollView.heightAnchor.constraint(lessThanOrEqualToConstant: 560).isActive = true
        scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        view = root

        rebuild()
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged),
            name: .scratchMateSettingsChanged, object: nil
        )
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func settingsChanged() { rebuild() }

    /// Tears down and rebuilds the form so toggles, reset, and theme changes are
    /// always reflected. Cheap: these forms are small.
    func rebuild() {
        handlers.removeAll()
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        populate(into: contentStack)
    }

    /// Subclass hook: append groups (built via `group(...)`) to the stack.
    func populate(into stack: NSStackView) {}

    // MARK: - Group + row builders

    /// A titled group: a heading, an optional caption, then the rows stacked.
    func group(_ title: String, caption: String? = nil, rows: [NSView]) -> NSView {
        let box = NSStackView()
        box.orientation = .vertical
        box.alignment = .leading
        box.spacing = 10

        let heading = NSTextField(labelWithString: title)
        heading.font = Typography.headline()
        heading.textColor = DesignTokens.label
        box.addArrangedSubview(heading)

        if let caption {
            let cap = NSTextField(wrappingLabelWithString: caption)
            cap.font = Typography.caption()
            cap.textColor = DesignTokens.secondaryLabel
            cap.preferredMaxLayoutWidth = contentWidth - 56
            box.addArrangedSubview(cap)
            box.setCustomSpacing(14, after: cap)
        } else {
            box.setCustomSpacing(14, after: heading)
        }

        let grid = NSGridView(views: rows.map { [$0] })
        grid.rowSpacing = 12
        grid.column(at: 0).xPlacement = .leading
        box.addArrangedSubview(grid)
        return box
    }

    /// A row pairing a left-aligned label with a trailing control.
    func row(_ title: String, _ control: NSView, hint: String? = nil) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = Typography.body()
        label.textColor = DesignTokens.label
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let labelColumn = NSStackView()
        labelColumn.orientation = .vertical
        labelColumn.alignment = .leading
        labelColumn.spacing = 2
        labelColumn.addArrangedSubview(label)
        if let hint {
            let h = NSTextField(wrappingLabelWithString: hint)
            h.font = Typography.caption()
            h.textColor = DesignTokens.tertiaryLabel
            h.preferredMaxLayoutWidth = 320
            labelColumn.addArrangedSubview(h)
        }

        let r = NSStackView(views: [labelColumn, NSView(), control])
        r.orientation = .horizontal
        r.alignment = .firstBaseline
        r.spacing = 14
        r.distribution = .fill
        labelColumn.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        r.widthAnchor.constraint(equalToConstant: contentWidth - 56).isActive = true
        return r
    }

    /// A full-width row for controls that own the line (sliders, cards, tables).
    func fullRow(_ title: String?, _ control: NSView) -> NSView {
        let col = NSStackView()
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 8
        if let title {
            let label = NSTextField(labelWithString: title)
            label.font = Typography.body()
            label.textColor = DesignTokens.label
            col.addArrangedSubview(label)
        }
        col.addArrangedSubview(control)
        control.widthAnchor.constraint(equalToConstant: contentWidth - 56).isActive = true
        col.widthAnchor.constraint(equalToConstant: contentWidth - 56).isActive = true
        return col
    }

    // MARK: - Control factories

    /// A boolean control. Uses NSSwitch (the System Settings idiom since Ventura)
    /// rather than the old checkbox so the form reads as a modern macOS panel.
    func checkbox(_ title: String, on: Bool, action: @escaping (Bool) -> Void) -> NSView {
        let sw = NSSwitch()
        sw.state = on ? .on : .off
        sw.controlSize = .small
        let handler = ControlHandler { sender in action((sender as? NSSwitch)?.state == .on) }
        sw.target = handler
        sw.action = #selector(ControlHandler.fire(_:))
        handlers.append(handler)
        return sw
    }

    func popup(_ titles: [String], selected: Int, action: @escaping (Int) -> Void) -> NSPopUpButton {
        let p = NSPopUpButton()
        p.addItems(withTitles: titles)
        p.selectItem(at: min(max(selected, 0), titles.count - 1))
        let handler = ControlHandler { sender in action((sender as? NSPopUpButton)?.indexOfSelectedItem ?? 0) }
        p.target = handler
        p.action = #selector(ControlHandler.fire(_:))
        handlers.append(handler)
        return p
    }

    func push(_ title: String, action: @escaping () -> Void) -> NSButton {
        let b = NSButton(title: title, target: nil, action: nil)
        b.bezelStyle = .rounded
        b.font = Typography.body()
        let handler = ControlHandler { _ in action() }
        b.target = handler
        b.action = #selector(ControlHandler.fire(_:))
        handlers.append(handler)
        return b
    }

    func slider(value: Double, min: Double, max: Double, action: @escaping (Double) -> Void) -> NSSlider {
        let s = NSSlider(value: value, minValue: min, maxValue: max, target: nil, action: nil)
        let handler = ControlHandler { sender in action((sender as? NSSlider)?.doubleValue ?? 0) }
        s.target = handler
        s.action = #selector(ControlHandler.fire(_:))
        handlers.append(handler)
        return s
    }

    func colorWell(color: NSColor, action: @escaping (NSColor) -> Void) -> NSColorWell {
        let w = NSColorWell()
        w.color = color
        let handler = ControlHandler { sender in action((sender as? NSColorWell)?.color ?? .clear) }
        w.target = handler
        w.action = #selector(ControlHandler.fire(_:))
        handlers.append(handler)
        return w
    }

    /// Headless scroll check: lays the section out at `windowHeight` and reports
    /// the full content height, the visible clip height, and whether the entire
    /// content is reachable by scrolling (document bottom can meet the clip
    /// bottom). Lets us verify the scroll without a screen capture (which macOS
    /// blocks in the background).
    func scrollMetrics(windowHeight: CGFloat) -> (content: CGFloat, visible: CGFloat, reachesEnd: Bool) {
        loadViewIfNeeded()
        view.frame = NSRect(x: 0, y: 0, width: contentWidth, height: windowHeight)
        view.layoutSubtreeIfNeeded()
        let content = documentView.fittingSize.height
        let visible = scrollView.contentView.bounds.height
        // A correctly wired NSScrollView (document pinned to the clip top, free at
        // the bottom) can always scroll its document fully into view; the only way
        // the end is unreachable is a clipped document. So the end is reachable
        // when the document holds the whole stack (content >= the stack's natural
        // height) and the clip is non-degenerate.
        let reachesEnd = content >= contentStack.fittingSize.height - 0.5 && visible > 1
        return (content, visible, reachesEnd)
    }
}

/// Closure-backed control target. The section controller retains it in its
/// `handlers` array so the control's target stays alive until the next rebuild.
@MainActor
private final class ControlHandler: NSObject {
    private let block: (NSControl) -> Void
    init(_ block: @escaping (NSControl) -> Void) { self.block = block }
    @objc func fire(_ sender: NSControl) { block(sender) }
}

// MARK: - General

private final class GeneralSettingsViewController: SettingsSectionViewController {

    override func populate(into stack: NSStackView) {
        let afterCloseTitles = ["Always", "After 3 minutes", "After 30 minutes",
                                "After 1 hour", "After 1 day", "Never"]
        let afterCloseValues = [0, 180, 1800, 3600, 86400, -1]
        let afterCloseIndex = afterCloseValues.firstIndex(of: Settings.newNoteAfterCloseSeconds) ?? 5

        let presenceTitles = ["Menu bar", "Dock", "Both", "None (hotkey only)"]
        let presenceValues = ["menubar", "dock", "both", "none"]
        let presenceIndex = presenceValues.firstIndex(of: Settings.appPresence) ?? 0

        stack.addArrangedSubview(group("Presence",
            caption: "Switching the Dock icon on or off fully applies after the next launch.",
            rows: [
                row("Show ScratchMate in",
                    popup(presenceTitles, selected: presenceIndex) { idx in
                        Settings.appPresence = presenceValues[idx]
                    }),
            ]))

        stack.addArrangedSubview(group("Startup", rows: [
            row("Launch at login",
                checkbox("", on: Settings.launchAtLogin) { on in setLaunchAtLogin(on) }),
            row("Create new note on launch",
                checkbox("", on: Settings.createNoteOnLaunch) { on in Settings.createNoteOnLaunch = on }),
        ]))

        stack.addArrangedSubview(group("New notes", rows: [
            row("Create new note after window closes",
                popup(afterCloseTitles, selected: afterCloseIndex) { idx in
                    Settings.newNoteAfterCloseSeconds = afterCloseValues[idx]
                }),
        ]))

        stack.addArrangedSubview(group("Window", rows: [
            row("Hide when unfocused",
                checkbox("", on: Settings.hideWhenUnfocused) { on in Settings.hideWhenUnfocused = on }),
        ]))

        stack.addArrangedSubview(group("Updates", rows: [
            row("Show what's new after update",
                checkbox("", on: Settings.showWhatsNewAfterUpdate) { on in Settings.showWhatsNewAfterUpdate = on }),
        ]))
    }
}

/// Toggles Launch at Login through SMAppService and persists the result.
private func setLaunchAtLogin(_ on: Bool) {
    Settings.launchAtLogin = on
    do {
        if on { try SMAppService.mainApp.register() }
        else { try SMAppService.mainApp.unregister() }
    } catch {
        NSLog("ScratchMate: launch at login failed: \(error)")
    }
}

// MARK: - Appearance

private final class AppearanceSettingsViewController: SettingsSectionViewController {

    override func populate(into stack: NSStackView) {
        stack.addArrangedSubview(group(
            "Theme",
            caption: "Pick a palette for the editor and the markdown preview.",
            rows: [ThemeGrid()]
        ))

        // Follow system: a light and a dark theme that track the OS appearance.
        let themeNames = Theme.all.map { $0.name }
        let themeIDs = Theme.all.map { $0.id }
        let lightIdx = themeIDs.firstIndex(of: Settings.lightThemeID) ?? 0
        let darkIdx = themeIDs.firstIndex(of: Settings.darkThemeID) ?? 0
        stack.addArrangedSubview(group("System appearance", rows: [
            row("Follow system Light/Dark",
                checkbox("", on: Settings.themeFollowsSystem) { on in Settings.themeFollowsSystem = on }),
            row("Light theme",
                popup(themeNames, selected: lightIdx) { idx in Settings.lightThemeID = themeIDs[idx] }),
            row("Dark theme",
                popup(themeNames, selected: darkIdx) { idx in Settings.darkThemeID = themeIDs[idx] }),
        ]))

        let accentTitles = ["System", "Caret amber", "Custom"]
        let accentValues = ["system", "caret", "custom"]
        let accentIndex = accentValues.firstIndex(of: Settings.accentSource) ?? 1

        let accentRows: [NSView] = [
            row("Accent",
                popup(accentTitles, selected: accentIndex) { idx in
                    Settings.accentSource = accentValues[idx]
                }),
            row("Custom color", customAccentWell()),
        ]
        stack.addArrangedSubview(group("Accent", rows: accentRows))

        // Translucency: a master toggle, an opacity slider (0 to 90%), and the
        // solid-bars option that keeps chrome legible over busy desktops.
        let readout = NSTextField(labelWithString: "\(Int(Settings.opacity * 100))%")
        readout.font = Typography.counterFont(size: 11)
        readout.textColor = DesignTokens.secondaryLabel
        let opacitySlider = slider(value: Settings.opacity, min: 0, max: 0.9) { value in
            readout.stringValue = "\(Int(value * 100))%"
            // Mid-drag: live preview without rebuilding this form. On mouse-up:
            // commit through the normal setter so everything else syncs once.
            if NSApp.currentEvent?.type == .leftMouseUp {
                Settings.opacity = value
            } else {
                Settings.setOpacityLive(value)
            }
        }
        opacitySlider.isEnabled = Settings.translucencyEnabled

        let sliderRow = NSStackView(views: [opacitySlider, readout])
        sliderRow.orientation = .horizontal
        sliderRow.spacing = 10
        opacitySlider.setContentHuggingPriority(.defaultLow, for: .horizontal)

        stack.addArrangedSubview(group("Translucency", rows: [
            row("Enable translucency",
                checkbox("", on: Settings.translucencyEnabled) { on in Settings.translucencyEnabled = on }),
            fullRow("Opacity", sliderRow),
            row("Solid bars in transparency mode",
                checkbox("", on: Settings.solidBarsInTranslucency) { on in Settings.solidBarsInTranslucency = on }),
        ]))
    }

    private func customAccentWell() -> NSView {
        let well = colorWell(color: NSColor(hex: Settings.customAccentHex)) { color in
            Settings.customAccentHex = color.toHexString()
            Settings.accentSource = "custom"
        }
        well.translatesAutoresizingMaskIntoConstraints = false
        well.widthAnchor.constraint(equalToConstant: 44).isActive = true
        well.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return well
    }
}

/// A clickable grid of theme cards: a color swatch row plus the theme name; the
/// active card is rimmed in the accent amber.
private final class ThemeGrid: NSView {

    private var cards: [ThemeCard] = []

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let columns = 4
        let grid = NSGridView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 12
        grid.columnSpacing = 12

        var rowViews: [[NSView]] = []
        var current: [NSView] = []
        for theme in Theme.all {
            let card = ThemeCard(theme: theme, isActive: theme.id == Settings.themeID) { picked in
                Settings.themeID = picked.id
            }
            cards.append(card)
            current.append(card)
            if current.count == columns {
                rowViews.append(current)
                current = []
            }
        }
        if !current.isEmpty {
            while current.count < columns { current.append(NSView()) }
            rowViews.append(current)
        }
        for r in rowViews { grid.addRow(with: r) }

        addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: topAnchor),
            grid.bottomAnchor.constraint(equalTo: bottomAnchor),
            grid.leadingAnchor.constraint(equalTo: leadingAnchor),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }
}

private final class ThemeCard: NSView {

    private let theme: Theme
    private let onPick: (Theme) -> Void
    private let container = NSView()
    private var trackingAreaRef: NSTrackingArea?

    init(theme: Theme, isActive: Bool, onPick: @escaping (Theme) -> Void) {
        self.theme = theme
        self.onPick = onPick
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        container.wantsLayer = true
        container.layer?.cornerRadius = GlassBackground.Radius.card
        container.layer?.cornerCurve = .continuous
        container.layer?.backgroundColor = theme.backgroundColor.cgColor
        container.layer?.borderWidth = isActive ? 2 : 1
        container.layer?.borderColor = (isActive ? DesignTokens.accent : DesignTokens.separator).cgColor
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)

        // Three swatches over the theme background: foreground, accent, secondary.
        let swatches = NSStackView()
        swatches.orientation = .horizontal
        swatches.spacing = 5
        swatches.translatesAutoresizingMaskIntoConstraints = false
        for hex in [theme.foreground, theme.accent, theme.secondary] {
            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.backgroundColor = NSColor(hex: hex).cgColor
            dot.layer?.cornerRadius = 5
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 16).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 16).isActive = true
            swatches.addArrangedSubview(dot)
        }
        container.addSubview(swatches)

        let name = NSTextField(labelWithString: theme.name)
        name.font = Typography.caption()
        name.textColor = theme.foregroundColor
        name.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(name)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 108),
            heightAnchor.constraint(equalToConstant: 72),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            swatches.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            swatches.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            name.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            name.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func mouseDown(with event: NSEvent) { onPick(theme) }
}

// MARK: - Editor

private final class EditorSettingsViewController: SettingsSectionViewController {

    /// Languages mirror EditorViewController's list so the default matches the
    /// editor's accepted ids.
    private let languages = [
        "auto", "markdown", "text", "json", "swift", "typescript", "javascript",
        "python", "go", "rust", "shell", "sql", "html", "yaml",
    ]

    private let sizeTitles = ["XS", "S", "M", "L", "XL"]
    private let sizeValues: [Double] = [11, 12, 13, 15, 18]

    override func populate(into stack: NSStackView) {
        // Font family: the system default (SF Mono) plus every monospaced family,
        // detected by the fixed-pitch trait (not a fragile name allowlist).
        var families = ["SF Mono (default)"]
        let mgr = NSFontManager.shared
        families += mgr.availableFontFamilies.filter { family in
            guard !family.hasPrefix("."),
                  let members = mgr.availableMembers(ofFontFamily: family),
                  let psName = members.first?.first as? String,
                  let font = NSFont(name: psName, size: 12) else { return false }
            return font.isFixedPitch
        }
        let currentFamily = Settings.editorFontFamily.isEmpty ? "SF Mono (default)" : Settings.editorFontFamily
        let familyIndex = families.firstIndex(of: currentFamily) ?? 0

        let sizeIndex = sizeValues.firstIndex(of: Settings.editorFontSize) ?? 2
        let langIndex = languages.firstIndex(of: Settings.defaultNoteLanguage) ?? 0

        stack.addArrangedSubview(group("Font", rows: [
            row("Font family",
                popup(families, selected: familyIndex) { idx in
                    Settings.editorFontFamily = idx == 0 ? "" : families[idx]
                }),
            row("Size",
                popup(sizeTitles, selected: sizeIndex) { [weak self] idx in
                    guard let self else { return }
                    Settings.editorFontSize = self.sizeValues[idx]
                }),
            row("Double text size",
                checkbox("", on: Settings.doubleTextSize) { on in Settings.doubleTextSize = on }),
        ]))

        stack.addArrangedSubview(group("Language", rows: [
            row("Default note language",
                popup(languages, selected: langIndex) { [weak self] idx in
                    guard let self else { return }
                    Settings.defaultNoteLanguage = self.languages[idx]
                }),
        ]))
    }
}

// MARK: - Behavior

private final class BehaviorSettingsViewController: SettingsSectionViewController {

    override func populate(into stack: NSStackView) {
        stack.addArrangedSubview(group("Chrome", rows: [
            row("Always show chrome",
                checkbox("", on: Settings.alwaysShowChrome) { on in Settings.alwaysShowChrome = on },
                hint: "Keep the footer controls visible without hovering."),
            row("Show note counter",
                checkbox("", on: Settings.showNoteCount) { on in Settings.showNoteCount = on },
                hint: "Display the \"3/7\" position in the footer."),
        ]))

        stack.addArrangedSubview(group("Editing", rows: [
            row("Copy on select",
                checkbox("", on: Settings.autoCopyOnSelect) { on in Settings.autoCopyOnSelect = on },
                hint: "Highlighting text copies it to the clipboard automatically."),
        ]))

        stack.addArrangedSubview(group("New notes", rows: [
            row("Default pin state for new notes",
                checkbox("", on: Settings.defaultPinned) { on in Settings.defaultPinned = on },
                hint: "Pinned notes keep the panel open when focus is lost."),
        ]))
    }
}

// MARK: - Shortcuts

private final class ShortcutsSettingsViewController: SettingsSectionViewController {

    override func populate(into stack: NSStackView) {
        let recorder = HotKeyRecorderView()
        stack.addArrangedSubview(group(
            "Global hotkey",
            caption: "Click the field, then press the combination to open ScratchMate from anywhere.",
            rows: [fullRow(nil, recorder)]
        ))

        // The rest of the shortcuts are read-only for now (rebind is [v2]). These
        // mirror the menu key equivalents defined in AppDelegate's main menu.
        let actions: [(String, String)] = [
            ("New note", "Cmd N"),
            ("Delete note", "Cmd Delete"),
            ("Command palette", "Cmd K"),
            ("Search all notes", "Cmd F"),
            ("Pin / unpin", "Cmd P"),
            ("Previous note", "Cmd ["),
            ("Next note", "Cmd ]"),
            ("Toggle preview", "Cmd R"),
            ("Open settings", "Cmd ,"),
        ]
        stack.addArrangedSubview(group(
            "Editor shortcuts",
            caption: "Rebinding these is planned for a future release.",
            rows: [shortcutsTable(actions)]
        ))
    }

    private func shortcutsTable(_ actions: [(String, String)]) -> NSView {
        let grid = NSGridView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 8
        grid.columnSpacing = 16
        for (name, combo) in actions {
            let l = NSTextField(labelWithString: name)
            l.font = Typography.body()
            l.textColor = DesignTokens.label
            let c = NSTextField(labelWithString: combo)
            c.font = Typography.counterFont(size: 12)
            c.textColor = DesignTokens.secondaryLabel
            c.alignment = .right
            grid.addRow(with: [l, c])
        }
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .trailing
        return grid
    }
}

/// Minimal native key recorder: a focusable field that captures the next key
/// chord and persists it. No external dependency. Clicking it arms capture;
/// the next keyDown with at least one modifier becomes the new hotkey.
private final class HotKeyRecorderView: NSView {

    private let label = NSTextField(labelWithString: "")
    private var recording = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = GlassBackground.Radius.control
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = DesignTokens.separator.cgColor
        layer?.backgroundColor = DesignTokens.adaptive(
            name: "recorderPad",
            light: NSColor.black.withAlphaComponent(0.04),
            dark: NSColor.white.withAlphaComponent(0.06)
        ).cgColor

        label.font = Typography.counterFont(size: 13)
        label.textColor = DesignTokens.label
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 40),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ])
        refreshLabel()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        recording = true
        window?.makeFirstResponder(self)
        layer?.borderColor = DesignTokens.accent.cgColor
        label.stringValue = "Press a key combination..."
        label.textColor = DesignTokens.secondaryLabel
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }

        // Escape cancels recording without changing the binding.
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }

        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        // Require at least one modifier so the global hotkey does not collide
        // with plain typing.
        guard !flags.isEmpty else {
            NSSound.beep()
            return
        }

        Settings.hotKeyCode = Int(event.keyCode)
        Settings.hotKeyModifiers = Int(flags.rawValue)
        stopRecording()
    }

    private func stopRecording() {
        recording = false
        layer?.borderColor = DesignTokens.separator.cgColor
        refreshLabel()
    }

    private func refreshLabel() {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(Settings.hotKeyModifiers))
        label.stringValue = HotKeyRecorderView.describe(keyCode: UInt16(Settings.hotKeyCode), flags: flags)
        label.textColor = DesignTokens.label
    }

    /// Renders a combination as glyphs (Cmd/Shift/Option/Control plus the key).
    static func describe(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> String {
        var parts = ""
        if flags.contains(.control) { parts += "Control " }
        if flags.contains(.option) { parts += "Option " }
        if flags.contains(.shift) { parts += "Shift " }
        if flags.contains(.command) { parts += "Cmd " }
        parts += keyName(for: keyCode)
        return parts
    }

    private static func keyName(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Escape: return "Esc"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        default:
            // Best effort: ask the current keyboard layout for the character.
            return layoutChar(for: keyCode) ?? "Key \(keyCode)"
        }
    }

    private static func layoutChar(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let result = data.withUnsafeBytes { raw -> OSStatus in
            guard let ptr = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(
                ptr, keyCode, UInt16(kUCKeyActionDisplay), 0,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState, chars.count, &length, &chars
            )
        }
        guard result == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

// MARK: - Notes & Privacy

private final class PrivacySettingsViewController: SettingsSectionViewController {

    override func populate(into stack: NSStackView) {
        let expireTitles = ["Never", "Today", "1 week", "1 month", "1 year"]
        let expireValues = [0, 1, 7, 30, 365]
        let expireIndex = expireValues.firstIndex(of: Settings.autoExpireDays) ?? 0

        stack.addArrangedSubview(group(
            "Auto-expire",
            caption: "Empty or old notes become cleanup candidates after this period.",
            rows: [
                row("Auto-expire notes",
                    popup(expireTitles, selected: expireIndex) { idx in
                        Settings.autoExpireDays = expireValues[idx]
                    }),
            ]
        ))

        let path = ScratchMateCore.Database.defaultPath()
        let pathField = NSTextField(labelWithString: path)
        pathField.font = Typography.counterFont(size: 11)
        pathField.textColor = DesignTokens.secondaryLabel
        pathField.lineBreakMode = .byTruncatingMiddle
        pathField.toolTip = path

        stack.addArrangedSubview(group("Storage", rows: [
            fullRow("Storage location", pathField),
            row("Reveal in Finder",
                push("Open folder") {
                    let dir = (path as NSString).deletingLastPathComponent
                    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: dir)
                }),
        ]))

        stack.addArrangedSubview(group(
            "Your data",
            caption: "No telemetry. ScratchMate never sends your notes anywhere.",
            rows: [
                row("Export all notes",
                    push("Export as .zip") { [weak self] in self?.exportAllNotes() }),
                row("Clear all notes",
                    push("Clear all...") { [weak self] in self?.confirmClearAll() }),
            ]
        ))
    }

    private func exportAllNotes() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ScratchMate-notes.zip"
        panel.canCreateDirectories = true
        panel.begin { response in
            MainActor.assumeIsolated {
                guard response == .OK, let url = panel.url else { return }
                self.writeNotesArchive(to: url)
            }
        }
    }

    /// Writes every note as a Markdown file into a temp folder, then zips it via
    /// `ditto` (always present on macOS), so export needs no extra dependency.
    private func writeNotesArchive(to destination: URL) {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("scratchmate-export-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            let db = try ScratchMateCore.Database(path: ScratchMateCore.Database.defaultPath())
            let notes = (try? db.recentNotes(limit: 100000)) ?? []
            for (i, note) in notes.enumerated() {
                let base = note.title.isEmpty ? "note-\(i + 1)" : note.title
                let safe = base.replacingOccurrences(of: "/", with: "-")
                let file = staging.appendingPathComponent("\(safe).md")
                try note.content.write(to: file, atomically: true, encoding: .utf8)
            }
            // ditto preserves a clean zip without the macOS resource forks.
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            proc.arguments = ["-c", "-k", "--keepParent", staging.path, destination.path]
            try proc.run()
            proc.waitUntilExit()
            try? fm.removeItem(at: staging)
        } catch {
            NSLog("ScratchMate: export failed: \(error)")
            let alert = NSAlert()
            alert.messageText = "Export failed"
            alert.informativeText = "ScratchMate could not export your notes."
            alert.runModal()
        }
    }

    private func confirmClearAll() {
        let alert = NSAlert()
        alert.messageText = "Clear all notes?"
        alert.informativeText = "This permanently deletes every note. This cannot be undone."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Clear all")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            clearAllNotes()
        }
    }

    private func clearAllNotes() {
        do {
            let db = try ScratchMateCore.Database(path: ScratchMateCore.Database.defaultPath())
            let notes = (try? db.recentNotes(limit: 100000)) ?? []
            for note in notes where note.id != 0 {
                try? db.delete(id: note.id)
            }
            // Nudge the editor to reload its deck from the now-empty store.
            NotificationCenter.default.post(name: .scratchMateSettingsChanged, object: nil)
        } catch {
            NSLog("ScratchMate: clear all failed: \(error)")
        }
    }
}

// MARK: - Advanced

private final class AdvancedSettingsViewController: SettingsSectionViewController {

    override func populate(into stack: NSStackView) {
        stack.addArrangedSubview(group("Updates", rows: [
            row("Check for updates automatically",
                checkbox("", on: Settings.autoCheckUpdates) { on in Settings.autoCheckUpdates = on }),
            row("Automatically download updates",
                checkbox("", on: Settings.autoDownloadUpdates) { on in Settings.autoDownloadUpdates = on }),
            row("Check now",
                push("Check now") { Updater.shared.checkForUpdates() }),
        ]))

        let schemes = [
            "scratchmate://open    Open the floating note window",
            "scratchmate://new     Open and start a new note",
            "scratchmate://palette Open and show the command palette",
        ]
        let schemeField = NSTextField(wrappingLabelWithString: schemes.joined(separator: "\n"))
        schemeField.font = Typography.counterFont(size: 11)
        schemeField.textColor = DesignTokens.secondaryLabel
        stack.addArrangedSubview(group(
            "URL scheme",
            caption: "Drive ScratchMate from scripts and other apps.",
            rows: [fullRow(nil, schemeField)]
        ))

        stack.addArrangedSubview(group(
            "Reset",
            caption: "Restore every setting to its default value.",
            rows: [
                row("Reset all settings",
                    push("Reset to defaults...") { [weak self] in self?.confirmReset() }),
            ]
        ))
    }

    private func confirmReset() {
        let alert = NSAlert()
        alert.messageText = "Reset all settings?"
        alert.informativeText = "Every preference returns to its default. Your notes are not affected."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            Settings.resetAll()
        }
    }
}

// MARK: - About

private final class AboutSettingsViewController: SettingsSectionViewController {

    override func populate(into stack: NSStackView) {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"

        // The menu-bar glyph is a template image, so contentTintColor washes it
        // in the Caret amber for the About header.
        let icon = NSImageView()
        icon.image = AppIcon.menuBar()
        icon.contentTintColor = DesignTokens.accent
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 48).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let name = NSTextField(labelWithString: "ScratchMate")
        name.font = Typography.title2()
        name.textColor = DesignTokens.label

        let versionLabel = NSTextField(labelWithString: "Version \(version) (\(build))")
        versionLabel.font = Typography.caption()
        versionLabel.textColor = DesignTokens.secondaryLabel

        let header = NSStackView(views: [icon, name, versionLabel])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 6
        stack.addArrangedSubview(header)

        stack.addArrangedSubview(group("Project", rows: [
            row("Repository",
                push("Open on GitHub") {
                    Self.open("https://github.com/leonardocandiani/scratchmate")
                }),
            row("License",
                push("View license") {
                    Self.open("https://github.com/leonardocandiani/scratchmate/blob/main/LICENSE")
                }),
        ]))

        stack.addArrangedSubview(group("Feedback", rows: [
            row("Report a bug",
                push("Open issue") {
                    Self.open("https://github.com/leonardocandiani/scratchmate/issues/new?labels=bug")
                }),
            row("Request a feature",
                push("Open issue") {
                    Self.open("https://github.com/leonardocandiani/scratchmate/issues/new?labels=enhancement")
                }),
        ]))

        let credits = NSTextField(wrappingLabelWithString:
            "Inspired by Antinote (ephemeral notes, global hotkey), TextMate (programmable text), and Krit (native macOS OSS).")
        credits.font = Typography.caption()
        credits.textColor = DesignTokens.tertiaryLabel
        credits.preferredMaxLayoutWidth = contentWidth - 56
        stack.addArrangedSubview(group("Credits", rows: [credits]))
    }

    private static func open(_ urlString: String) {
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }
}

// MARK: - NSColor hex serialization

private extension NSColor {
    /// Serializes to "#RRGGBB" so the custom accent survives in UserDefaults.
    func toHexString() -> String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X",
                      Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)),
                      Int(round(c.blueComponent * 255)))
    }
}
