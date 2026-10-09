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
        let arcRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: browser.id).isEmpty
        switch (target.profile, ProfileSource.forBundleID(browser.id)) {
        case (let space?, .arcSpaces) where arcRunning:
            openInArcSpace(url, spaceID: space.id) { message in
                presentFailure(browser: target.label, message: message, retry: retry)
            }
        case (_, .arcSpaces):
            // Arc not running: limited support. Open it the usual way, where Arc's settings send external links.
            NSWorkspace.shared.open([url], withApplicationAt: browser.appURL, configuration: configuration) { _, error in report(error) }
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

    /// Arc has no launch argument for a Space, so the link goes through its AppleScript interface.
    /// Space ID and URL are passed as arguments, never spliced into the script.
    /// Only used while Arc is running: a tab made during Arc's startup may never load.
    private static let arcScript = """
        on run argv
            tell application id "\(ProfileSource.arcBundleID)"
                if (count of windows) is 0 then make new window
                repeat 50 times
                    if (count of windows) > 0 then exit repeat
                    delay 0.1
                end repeat
                tell front window to tell space id (item 1 of argv)
                    focus
                    make new tab with properties {URL:(item 2 of argv)}
                end tell
                activate
            end tell
        end run
        """

    /// Runs off the main thread so a cold Arc start does not block the app.
    private static func openInArcSpace(_ url: URL, spaceID: String, onFailure: @escaping @MainActor (String) -> Void) {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/osascript")
        process.arguments = ["-e", arcScript, spaceID, url.absoluteString]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = FileHandle.nullDevice
        process.terminationHandler = { process in
            guard process.terminationStatus != 0 else { return }
            let output = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let message = output.contains("-1743")
                ? "Browser Picker isn't allowed to control Arc. Allow it in System Settings → Privacy & Security → Automation."
                : output.trimmingCharacters(in: .whitespacesAndNewlines)
            Task { @MainActor in onFailure(message) }
        }
        do {
            try process.run()
        } catch {
            onFailure(error.localizedDescription)
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
