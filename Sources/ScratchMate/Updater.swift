import AppKit

#if canImport(Sparkle)
import Sparkle

/// Auto-update via Sparkle. Active whenever the Sparkle dependency is present in
/// Package.swift (see SETUP.md). Reads SUFeedURL/SUPublicEDKey from Info.plist.
@MainActor final class Updater {
    static let shared = Updater()
    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
        )
        // Mirror the user's preferences onto the live updater.
        let updater = controller.updater
        updater.automaticallyChecksForUpdates = Settings.autoCheckUpdates
        updater.automaticallyDownloadsUpdates = Settings.autoDownloadUpdates
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged),
            name: .scratchMateSettingsChanged, object: nil
        )
    }

    @objc private func settingsChanged() {
        controller.updater.automaticallyChecksForUpdates = Settings.autoCheckUpdates
        controller.updater.automaticallyDownloadsUpdates = Settings.autoDownloadUpdates
    }

    func checkForUpdates() { controller.checkForUpdates(nil) }
}
#else

/// Fallback without Sparkle: "Check for Updates" opens the releases page.
/// Once Sparkle is added to the Package, this version goes away and the one above takes over.
@MainActor final class Updater {
    static let shared = Updater()
    func checkForUpdates() {
        if let url = URL(string: "https://github.com/leonardocandiani/scratchmate/releases/latest") {
            NSWorkspace.shared.open(url)
        }
    }
}
#endif
