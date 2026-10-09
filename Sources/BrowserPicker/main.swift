import AppKit
import BrowserPickerCore

if CommandLine.arguments.contains("--list-browsers") {
    let catalog = BrowserCatalog(locator: WorkspaceLocator(), ownBundleID: Bundle.main.bundleIdentifier)
    for target in catalog.targets() {
        print("\(target.label)\t\(target.browser.id)\t\(target.profile?.id ?? "-")\t\(target.browser.appURL.path)")
    }
    let blocked = catalog.blockedBrowsers()
    if !blocked.isEmpty {
        FileHandle.standardError.write(Data("Profiles blocked by macOS (needs Full Disk Access): \(blocked.map(\.name).joined(separator: ", "))\n".utf8))
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
