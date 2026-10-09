import AppKit
import BrowserPickerCore

@MainActor
enum BrowserLauncher {
    /// Opens `url` in `browser`. On failure shows an alert; `retry` is called if the user wants another browser.
    static func open(_ url: URL, in browser: Browser, retry: @escaping @MainActor () -> Void) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: browser.appURL, configuration: configuration) { _, error in
            guard let error else { return }
            let message = error.localizedDescription
            Task { @MainActor in
                presentFailure(browser: browser.name, message: message, retry: retry)
            }
        }
    }

    private static func presentFailure(browser: String, message: String, retry: @MainActor () -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't open the link in \(browser)"
        alert.informativeText = message
        alert.addButton(withTitle: "Choose Another Browser")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            retry()
        } else if NSApp.isActive {
            NSApp.hide(nil)
        }
    }
}
