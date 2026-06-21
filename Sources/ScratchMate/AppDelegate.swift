import AppKit
import ScratchMateCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panel: ScratchPanel?
    private var editor: EditorViewController?
    private var hotKey: HotKey?
    private let registry = CommandRegistry()
    private var database: Database?
    private let welcomeController = WelcomeWindowController()
    private let whatsNewController = WhatsNewWindowController()
    private var lastHiddenAt: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        openDatabase()
        // Purge expired notes BEFORE building the panel, otherwise the editor loads
        // the deck (including notes expiring this run) and shows them this session.
        _ = try? database?.purgeExpired()
        buildMenu()
        buildPanel()
        registerHotKey()
        registerURLScheme()
        applyAppPresence()  // activation policy + status item, from the presence setting
        NotificationCenter.default.addObserver(
            self, selector: #selector(applyAppPresence),
            name: .scratchMateSettingsChanged, object: nil
        )

        // First open up front, so the user sees it is running.
        panel?.show()
        if Settings.createNoteOnLaunch { editor?.newNote() }

        // Snapshot mode renders a single surface headlessly: skip onboarding so a
        // modal welcome/what's-new window never blocks the snapshot run loop.
        let isSnapshot = ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("SCRATCHMATE_SNAPSHOT") }
        if !isSnapshot {
            // Arm auto-update at boot: instantiating the updater starts Sparkle's
            // scheduled check and applies the autoCheck/autoDownload preferences,
            // instead of only running on a manual "Check for Updates".
            _ = Updater.shared

            // Onboarding: welcome card on first launch, otherwise the What's New
            // panel when the version changed since last seen (never both, never on
            // a fresh install). welcomeController.showIfNeeded() no-ops after run 1.
            welcomeController.showIfNeeded()
            whatsNewController.showIfNeeded()
        }

        snapshotIfRequested()
    }

    /// Visual capture mode (no Screen Recording): delegates to the editor to render
    /// itself. SCRATCHMATE_SNAPSHOT = editor; SCRATCHMATE_SNAPSHOT_PREVIEW = preview.
    private func snapshotIfRequested() {
        let env = ProcessInfo.processInfo.environment
        if let path = env["SCRATCHMATE_SNAPSHOT_PREVIEW"] {
            editor?.snapshotPreview(to: path)
        } else if let path = env["SCRATCHMATE_SNAPSHOT_SETTINGS"] {
            SettingsWindowController.shared.snapshot(to: path)
        } else if env["SCRATCHMATE_SNAPSHOT_DIAG_SCROLL"] != nil {
            SettingsWindowController.shared.diagnoseScroll()
        } else if let path = env["SCRATCHMATE_SNAPSHOT_WELCOME"] {
            welcomeController.snapshot(to: path)
        } else if let path = env["SCRATCHMATE_SNAPSHOT"] {
            editor?.snapshotEditor(to: path)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        editor?.saveCurrentNow()
    }

    // MARK: - Setup

    private func openDatabase() {
        do {
            database = try Database(path: Database.defaultPath())
        } catch {
            NSLog("ScratchMate: could not open the database (\(error)). Continuing without persistence.")
            database = nil
        }
    }

    // MARK: - App presence

    /// Maps the presence setting to an activation policy. "menubar" stays an
    /// accessory agent; "dock"/"both" show a Dock icon; "none" hides everywhere.
    static func activationPolicy(for presence: String) -> NSApplication.ActivationPolicy {
        switch presence {
        case "dock", "both": return .regular
        case "none": return .prohibited
        default: return .accessory
        }
    }

    /// Whether the menu bar status item should be shown for a given presence.
    static func showsStatusItem(for presence: String) -> Bool {
        presence == "menubar" || presence == "both"
    }

    /// Applies the current presence setting: activation policy plus showing or
    /// removing the status item. Safe to call again when the setting changes.
    @objc private func applyAppPresence() {
        NSApp.setActivationPolicy(Self.activationPolicy(for: Settings.appPresence))
        let shouldShow = Self.showsStatusItem(for: Settings.appPresence)
        if shouldShow, statusItem == nil {
            buildStatusItem()
        } else if !shouldShow, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = AppIcon.menuBar()
        item.button?.toolTip = "ScratchMate"

        let menu = NSMenu()
        menu.addItem(
            withTitle: "Open ScratchMate  (⌘⇧Space)",
            action: #selector(togglePanel), keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    private func buildPanel() {
        let editorVC = EditorViewController(registry: registry, database: database)
        let panel = ScratchPanel(contentViewController: editorVC)
        panel.title = "ScratchMate"
        panel.onResignKey = { [weak self] in
            // Hide on blur, except with the palette open or the panel pinned.
            guard let self, let editor = self.editor else { return }
            if editor.isPaletteOpen || editor.isPinned || editor.isSearchOpen { return }
            editor.saveCurrentNow()
            if !Settings.hideWhenUnfocused { return }  // user opted to keep it visible on blur
            self.lastHiddenAt = Date()
            self.panel?.orderOut(nil)
        }
        self.editor = editorVC
        self.panel = panel
    }

    private func registerHotKey() {
        hotKey = HotKey { [weak self] in self?.togglePanel() }
    }

    private func registerURLScheme() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    // MARK: - Actions

    @objc private func togglePanel() {
        if panel?.isVisible == true {
            lastHiddenAt = Date()
            panel?.toggle()
        } else {
            maybeNewNoteAfterClose()
            panel?.toggle()
        }
    }

    /// Start a fresh note when reopening after the window stayed closed longer
    /// than Settings.newNoteAfterCloseSeconds (-1 disables, 0 = always).
    private func maybeNewNoteAfterClose() {
        let secs = Settings.newNoteAfterCloseSeconds
        guard secs >= 0, let hidden = lastHiddenAt else { return }
        if Date().timeIntervalSince(hidden) >= Double(secs) { editor?.newNote() }
    }

    @objc private func openPalette() {
        if panel?.isVisible != true { panel?.show() }
        editor?.openPalette()
    }

    @objc private func checkForUpdates() {
        Updater.shared.checkForUpdates()
    }

    @objc private func showWhatsNew() {
        whatsNewController.showManually()
    }

    // MARK: - URL scheme: scratchmate://...

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString),
              url.scheme == "scratchmate"
        else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let action = url.host ?? "open"
        let params = Dictionary(
            uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )

        switch action {
        case "open":
            panel?.show()
        case "new":
            panel?.show()
            if let text = params["text"]?.removingPercentEncoding {
                editor?.execute(makeInsertCommand(text: text))
            }
        case "palette":
            openPalette()
        default:
            panel?.show()
        }
    }

    /// Ephemeral command that inserts text coming from the URL scheme.
    private func makeInsertCommand(text: String) -> TextCommand {
        TextCommand(
            id: "url-insert", title: "Insert via URL", trigger: "::url-insert",
            input: .none, output: .insert
        ) { _, _ in text }
    }

    // MARK: - Menu (key equivalents only work with a menu mounted)

    private func buildMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About ScratchMate",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(withTitle: "What's New", action: #selector(showWhatsNew), keyEquivalent: "")
        appMenu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: Selector(("openSettings")), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit ScratchMate", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        // Edit menu (required for ⌘Z/⌘X/⌘C/⌘V/⌘A in NSTextView)
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        // Note menu (actions resolved through the responder chain in EditorViewController)
        let noteItem = NSMenuItem()
        mainMenu.addItem(noteItem)
        let noteMenu = NSMenu(title: "Note")
        noteMenu.addItem(withTitle: "New Note", action: Selector(("newNoteAction")), keyEquivalent: "n")
        noteMenu.addItem(withTitle: "Previous Note", action: Selector(("goOlder")), keyEquivalent: "[")
        noteMenu.addItem(withTitle: "Next Note", action: Selector(("goNewer")), keyEquivalent: "]")
        noteMenu.addItem(withTitle: "Pin to Screen", action: Selector(("togglePin")), keyEquivalent: "p")
        noteMenu.addItem(.separator())
        let del = noteMenu.addItem(withTitle: "Delete Note", action: Selector(("deleteCurrentNote")), keyEquivalent: "\u{8}")
        del.keyEquivalentModifierMask = [.command]
        noteItem.submenu = noteMenu

        // Commands menu
        let cmdItem = NSMenuItem()
        mainMenu.addItem(cmdItem)
        let cmdMenu = NSMenu(title: "Commands")
        cmdMenu.addItem(withTitle: "Command Palette", action: #selector(openPalette), keyEquivalent: "k")
        cmdMenu.addItem(withTitle: "Find Across Notes", action: Selector(("openSearchAction")), keyEquivalent: "f")
        cmdMenu.addItem(withTitle: "Toggle Preview", action: Selector(("togglePreview")), keyEquivalent: "r")
        cmdMenu.addItem(withTitle: "Toggle Window", action: #selector(togglePanel), keyEquivalent: "j")
        cmdItem.submenu = cmdMenu

        NSApp.mainMenu = mainMenu
    }
}
