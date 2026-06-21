import AppKit

// App entry point. The activation policy follows the user's app-presence setting
// (menu bar agent by default: no Dock icon, a floating window summoned by hotkey).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(AppDelegate.activationPolicy(for: Settings.appPresence))
app.run()
