import AppKit

/// First-launch onboarding: a single Liquid Glass card that introduces Caret
/// (ScratchMate), shows the global hotkey, the `::` commands, and how to move
/// between notes. There is no permission page: ScratchMate registers its hotkey
/// through Carbon's RegisterEventHotKey, so it needs neither Accessibility nor
/// Screen Recording.
///
/// Gating lives in plain UserDefaults under "hasLaunchedBefore" (read and written
/// here directly, never through Settings, so it does not collide with the
/// preferences layer). Closing via the traffic light counts as seen too, so the
/// card never returns after the first run.
final class WelcomeWindowController: NSObject, NSWindowDelegate {

    private static let hasLaunchedKey = "hasLaunchedBefore"

    private var window: NSWindow?

    private let cardWidth: CGFloat = 560
    private let cardHeight: CGFloat = 520

    private let accessibility = AccessibilityMonitor()

    private var reduceMotion: Bool { accessibility.reduceMotion }

    private var hasLaunchedBefore: Bool {
        UserDefaults.standard.bool(forKey: Self.hasLaunchedKey)
    }

    private func markLaunched() {
        UserDefaults.standard.set(true, forKey: Self.hasLaunchedKey)
    }

    /// Shows the welcome card only on the very first launch. No-op afterwards.
    func showIfNeeded() {
        guard !hasLaunchedBefore else { return }
        showWindow()
    }

    // MARK: - Window

    private func showWindow() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: cardWidth, height: cardHeight),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        // Match the active theme so the onboarding card never renders light over a
        // dark app (or vice versa) when the system appearance differs.
        win.appearance = NSAppearance(named: Theme.byID(Settings.themeID).isDark ? .darkAqua : .aqua)
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self

        // Liquid Glass backing for the whole card. GlassBackground guards
        // #available internally: real glass on macOS 26, HUD blur before it.
        // Content lives in a container that becomes the glass contentView, so the
        // material composes under it on macOS 26 (Apple's documented pattern).
        let content = NSView(frame: NSRect(x: 0, y: 0, width: cardWidth, height: cardHeight))
        buildContent(in: content)
        let background = GlassBackground.panel(wrapping: content, cornerRadius: GlassBackground.Radius.panel)
        background.frame = NSRect(x: 0, y: 0, width: cardWidth, height: cardHeight)
        background.autoresizingMask = [.width, .height]
        win.contentView = background

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        window = win

        animateEntrance(in: content)
    }

    /// Renders the welcome card to a PNG via cacheDisplay, then exits. Verifies the
    /// onboarding layout headlessly: the glass blur is not captured, but the
    /// content layout, spacing, and copy are, over a solid theme background.
    func snapshot(to path: String) {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: cardWidth, height: cardHeight))
        buildContent(in: content)
        let theme = Theme.byID(Settings.themeID)
        let host = NSView(frame: content.bounds)
        host.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
        host.wantsLayer = true
        host.layer?.backgroundColor = theme.backgroundColor.cgColor
        host.addSubview(content)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
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

    // MARK: - Content

    private func buildContent(in container: NSView) {
        let w = container.bounds.width
        var y = container.bounds.height - 36

        // Brand mark: the Caret glyph in amber inside a tinted glass chip.
        let markSize: CGFloat = 72
        let glyphHost = NSView(frame: NSRect(x: 0, y: 0, width: markSize, height: markSize))
        let glyphSize: CGFloat = 40
        let glyph = NSImageView(frame: NSRect(
            x: (markSize - glyphSize) / 2, y: (markSize - glyphSize) / 2,
            width: glyphSize, height: glyphSize
        ))
        glyph.image = caretMark(size: glyphSize)
        glyph.imageScaling = .scaleProportionallyUpOrDown
        glyphHost.addSubview(glyph)

        let chip = GlassBackground.panel(
            wrapping: glyphHost,
            cornerRadius: GlassBackground.Radius.card,
            tint: DesignTokens.accentTint
        )
        chip.frame = NSRect(x: (w - markSize) / 2, y: y - markSize, width: markSize, height: markSize)
        chip.identifier = NSUserInterfaceItemIdentifier("welcome-mark")
        container.addSubview(chip)
        y -= markSize + 14

        // Title.
        let title = NSTextField(labelWithString: "Welcome to ScratchMate")
        title.font = .boldSystemFont(ofSize: 25)
        title.textColor = DesignTokens.label
        title.alignment = .center
        title.frame = NSRect(x: 20, y: y - 30, width: w - 40, height: 30)
        container.addSubview(title)
        y -= 36

        // Tagline (two short lines on what the app is).
        let tagline = NSTextField(wrappingLabelWithString:
            "A programmable scratchpad for developers. Ephemeral notes, live "
            + "preview, and text commands, one keystroke away.")
        tagline.font = .systemFont(ofSize: 13)
        tagline.textColor = DesignTokens.secondaryLabel
        tagline.alignment = .center
        tagline.frame = NSRect(x: 48, y: y - 40, width: w - 96, height: 40)
        container.addSubview(tagline)
        y -= 56

        // Hotkey row: keycaps for the global toggle.
        let hotkeyHost = makeHotkeyRow(width: w)
        hotkeyHost.frame.origin = NSPoint(x: (w - hotkeyHost.frame.width) / 2, y: y - hotkeyHost.frame.height)
        container.addSubview(hotkeyHost)
        y -= hotkeyHost.frame.height + 10

        let hotkeyCaption = NSTextField(labelWithString: "Summon ScratchMate from any app")
        hotkeyCaption.font = .systemFont(ofSize: 11.5)
        hotkeyCaption.textColor = DesignTokens.tertiaryLabel
        hotkeyCaption.alignment = .center
        hotkeyCaption.frame = NSRect(x: 20, y: y - 16, width: w - 40, height: 16)
        container.addSubview(hotkeyCaption)
        y -= 30

        // Commands grid: the `::` triggers as glass chips.
        let commands: [(String, String)] = [
            ("::date",  "ISO 8601 timestamp"),
            ("::json",  "Pretty-print JSON"),
            ("::sort",  "Sort the lines"),
            ("::uuid",  "Generate a UUID"),
        ]
        let colWidth = (w - 96) / 2
        let rowHeight: CGFloat = 36
        for (i, command) in commands.enumerated() {
            let col = i % 2
            let row = i / 2
            let x = 48 + CGFloat(col) * colWidth
            let rowY = y - CGFloat(row + 1) * rowHeight

            let tagW: CGFloat = 64
            let tag = NSTextField(labelWithString: command.0)
            tag.font = Typography.editorFont(size: 11.5, weight: .semibold)
            tag.textColor = DesignTokens.accent
            tag.alignment = .center
            tag.wantsLayer = true
            tag.layer?.backgroundColor = DesignTokens.accent.withAlphaComponent(0.12).cgColor
            tag.layer?.cornerRadius = GlassBackground.Radius.pill
            tag.layer?.cornerCurve = .continuous
            tag.frame = NSRect(x: x, y: rowY + (rowHeight - 22) / 2, width: tagW, height: 22)
            container.addSubview(tag)

            let label = NSTextField(labelWithString: command.1)
            label.font = .systemFont(ofSize: 11.5)
            label.textColor = DesignTokens.label
            label.lineBreakMode = .byTruncatingTail
            label.frame = NSRect(
                x: x + tagW + 10, y: rowY + (rowHeight - 16) / 2,
                width: colWidth - tagW - 14, height: 16
            )
            container.addSubview(label)
        }
        y -= CGFloat(2) * rowHeight + 8

        let commandsCaption = NSTextField(labelWithString: "Type :: (or press Cmd K) to run a command")
        commandsCaption.font = .systemFont(ofSize: 11.5)
        commandsCaption.textColor = DesignTokens.tertiaryLabel
        commandsCaption.alignment = .center
        commandsCaption.frame = NSRect(x: 20, y: y - 16, width: w - 40, height: 16)
        container.addSubview(commandsCaption)
        y -= 30

        // Navigation hint.
        let navHint = NSTextField(wrappingLabelWithString:
            "Swipe sideways or use Cmd [ and Cmd ] to move between notes. "
            + "Press Cmd , for themes, shortcuts and more.")
        navHint.font = .systemFont(ofSize: 11.5)
        navHint.textColor = DesignTokens.secondaryLabel
        navHint.alignment = .center
        navHint.frame = NSRect(x: 48, y: y - 34, width: w - 96, height: 34)
        container.addSubview(navHint)

        // Primary action pinned to the bottom.
        let getStarted = makePrimaryButton(title: "Get Started", action: #selector(getStartedClicked))
        getStarted.keyEquivalent = "\r"
        getStarted.frame = NSRect(x: (w - 160) / 2, y: 26, width: 160, height: 34)
        container.addSubview(getStarted)
    }

    /// Builds the centered keycap row for the global hotkey (Cmd Shift Space).
    private func makeHotkeyRow(width: CGFloat) -> NSView {
        let keys = ["⌘", "⇧", "Space"]
        let gap: CGFloat = 8
        let height: CGFloat = 32
        var x: CGFloat = 0
        let host = NSView()
        for key in keys {
            let isWide = key == "Space"
            let keyW: CGFloat = isWide ? 76 : 38
            let cap = makeKeycap(title: key, width: keyW, height: height)
            cap.frame.origin = NSPoint(x: x, y: 0)
            host.addSubview(cap)
            x += keyW + gap
        }
        host.frame = NSRect(x: 0, y: 0, width: x - gap, height: height)
        return host
    }

    /// A single keycap: label on a faint, rimmed pad.
    private func makeKeycap(title: String, width: CGFloat, height: CGFloat) -> NSView {
        let cap = NSTextField(labelWithString: title)
        cap.font = .systemFont(ofSize: 14, weight: .semibold)
        cap.textColor = DesignTokens.label
        cap.alignment = .center
        cap.wantsLayer = true
        cap.layer?.backgroundColor = DesignTokens.label.withAlphaComponent(0.08).cgColor
        cap.layer?.cornerRadius = GlassBackground.Radius.pill
        cap.layer?.cornerCurve = .continuous
        cap.layer?.borderWidth = 1
        cap.layer?.borderColor = DesignTokens.label.withAlphaComponent(0.12).cgColor
        cap.frame = NSRect(x: 0, y: 0, width: width, height: height)
        return cap
    }

    /// Native rounded push button tinted with the Caret accent. AppKit owns the
    /// bezel height and label contrast.
    private func makePrimaryButton(title: String, action: Selector) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.bezelStyle = .rounded
        btn.controlSize = .large
        btn.bezelColor = DesignTokens.accent
        return btn
    }

    /// The "Caret" mark: a bracket that opens and never closes, embracing `::`.
    /// Same glyph language as the menu-bar icon, drawn in the amber accent.
    private func caretMark(size: CGFloat) -> NSImage {
        let accent = DesignTokens.accent
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            accent.setFill()
            let s = size / 18  // glyph authored on an 18pt grid (matches AppIcon)
            func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat = 0.7) {
                NSBezierPath(
                    roundedRect: NSRect(x: x * s, y: y * s, width: w * s, height: h * s),
                    xRadius: r * s, yRadius: r * s
                ).fill()
            }
            rr(2.4, 3.0, 1.7, 12.0)   // bracket stem
            rr(2.4, 13.3, 4.2, 1.7)   // top arm
            rr(2.4, 3.0, 4.2, 1.7)    // bottom arm
            let d: CGFloat = 2.3
            for (x, y) in [(8.7, 10.0), (8.7, 5.0), (12.5, 10.0), (12.5, 5.0)] as [(CGFloat, CGFloat)] {
                rr(x, y, d, d, 0.8)
            }
            return true
        }
        return image
    }

    // MARK: - Entrance

    /// Slide-and-fade entrance for the card content (0.28s), skipped under
    /// Reduce Motion. The brand mark also springs in for a little life.
    private func animateEntrance(in container: NSView) {
        guard !reduceMotion else { return }

        container.wantsLayer = true
        let shift: CGFloat = 18
        for subview in container.subviews {
            subview.wantsLayer = true
            guard let layer = subview.layer else { continue }
            let slide = CABasicAnimation(keyPath: "transform.translation.y")
            slide.fromValue = -shift
            slide.toValue = 0
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            let group = CAAnimationGroup()
            group.animations = [slide, fade]
            group.duration = 0.28
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(group, forKey: "entrance")
        }

        if let mark = container.subviews.first(where: {
            $0.identifier?.rawValue == "welcome-mark"
        }), let layer = mark.layer {
            layer.position = CGPoint(x: mark.frame.midX, y: mark.frame.midY)
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            let spring = CASpringAnimation(keyPath: "transform.scale")
            spring.fromValue = 0.7
            spring.toValue = 1.0
            spring.stiffness = 300
            spring.damping = 20
            spring.initialVelocity = 4
            spring.duration = spring.settlingDuration
            layer.add(spring, forKey: "markSpring")
        }
    }

    // MARK: - Actions

    @objc private func getStartedClicked() {
        markLaunched()
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        // Dismissing via the traffic light counts as seen too, never re-show.
        markLaunched()
        window = nil
    }
}
