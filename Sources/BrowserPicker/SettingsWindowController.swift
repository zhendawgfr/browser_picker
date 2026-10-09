import AppKit
import BrowserPickerCore
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let ruleStore: RuleStore
    private let catalog: BrowserCatalog
    private let defaultBrowser: DefaultBrowserService

    init(ruleStore: RuleStore, catalog: BrowserCatalog, defaultBrowser: DefaultBrowserService) {
        self.ruleStore = ruleStore
        self.catalog = catalog
        self.defaultBrowser = defaultBrowser
    }

    func show() {
        if window == nil {
            let view = SettingsView(ruleStore: ruleStore, catalog: catalog, defaultBrowser: defaultBrowser)
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "Browser Picker Settings"
            w.styleMask = [.titled, .closable, .resizable]
            w.setContentSize(CGSize(width: 480, height: 440))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
