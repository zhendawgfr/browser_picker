import AppKit
import BrowserPickerCore

@MainActor
enum BrowserLauncher {
    /// Opens `url` in `target`. On failure shows an alert; `retry` is called if the user wants another browser.
    static func open(_ url: URL, in target: BrowserTarget, retry: @escaping @MainActor () -> Void) {
        let browser = target.browser
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let report: @Sendable (Error?) -> Void = { error in
            guard let error else { return }
            let message = error.localizedDescription
            Task { @MainActor in
                presentFailure(browser: target.label, message: message, retry: retry)
            }
        }
        switch (target.profile, ProfileSource.forBundleID(browser.id)) {
        case (let profile?, .firefox(let root)?):
            // Firefox opens its own profiles this way: a new instance hands the URL to an instance already
            // running that profile, through Firefox's remoting, and exits.
            guard let folder = firefoxProfileFolder(profile.id, root: root) else {
                presentFailure(browser: target.label, message: "The profile “\(profile.name)” no longer exists.", retry: retry)
                return
            }
            configuration.arguments = ["-foreground", "--profile", folder.path, "-new-tab", url.absoluteString]
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: browser.appURL, configuration: configuration) { _, error in report(error) }
        case (let profile?, _):
            // An Apple Event carries no profile. Launch with arguments instead; a new instance hands them to a
            // running browser through Chromium's process singleton and exits.
            configuration.arguments = ["--profile-directory=\(profile.id)", url.absoluteString]
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: browser.appURL, configuration: configuration) { _, error in report(error) }
        case (nil, _):
            NSWorkspace.shared.open([url], withApplicationAt: browser.appURL, configuration: configuration) { _, error in report(error) }
        }
    }

    /// A Firefox profile's folder: its id, relative to Firefox's root folder or absolute. `nil` when the folder is
    /// gone, since `--profile` would make Firefox create a fresh, empty profile there.
    private static func firefoxProfileFolder(_ id: String, root: String) -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = (id.hasPrefix("/") ? URL(filePath: id) : support.appending(path: root).appending(path: id)).standardizedFileURL
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) && isDirectory.boolValue ? folder : nil
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
