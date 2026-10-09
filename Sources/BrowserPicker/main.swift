import AppKit
import BrowserPickerCore

if CommandLine.arguments.contains("--list-browsers") {
    let catalog = BrowserCatalog(locator: WorkspaceLocator(), ownBundleID: Bundle.main.bundleIdentifier)
    for browser in catalog.browsers() {
        print("\(browser.name)\t\(browser.id)\t\(browser.appURL.path)")
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
