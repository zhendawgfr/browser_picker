import AppKit
import BrowserPickerCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let ruleStore = RuleStore()
    private let catalog = BrowserCatalog(locator: WorkspaceLocator(), ownBundleID: Bundle.main.bundleIdentifier)
    private let defaultBrowser = DefaultBrowserService()
    private lazy var coordinator = LinkCoordinator(ruleStore: ruleStore, catalog: catalog)
    private lazy var settings = SettingsWindowController(ruleStore: ruleStore, catalog: catalog, defaultBrowser: defaultBrowser)
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(openSettings: { [weak self] in self?.settings.show() })
        catalog.warmUp()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        coordinator.enqueue(urls, overrideHeld: NSEvent.modifierFlags.contains(.option))
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return true
    }
}
