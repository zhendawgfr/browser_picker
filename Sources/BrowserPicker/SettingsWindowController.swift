import AppKit
import BrowserPickerCore
import SwiftUI

/// Owns the Settings window. While it is open the app has a Dock icon and a main menu; once it closes
/// the app goes back to the menu bar only.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let ruleStore: RuleStore
    private let catalog: BrowserCatalog
    private let defaultBrowser: DefaultBrowserService

    init(ruleStore: RuleStore, catalog: BrowserCatalog, defaultBrowser: DefaultBrowserService) {
        self.ruleStore = ruleStore
        self.catalog = catalog
        self.defaultBrowser = defaultBrowser
        super.init()
    }

    func show() {
        if window == nil {
            let view = SettingsView(ruleStore: ruleStore, catalog: catalog, defaultBrowser: defaultBrowser)
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "Browser Picker Settings"
            w.styleMask = [.titled, .closable, .resizable]
            w.setContentSize(CGSize(width: 480, height: 440))
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        if NSApp.mainMenu == nil { NSApp.mainMenu = makeMainMenu() }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Hand focus back to the app the user came from.
        NSApp.hide(nil)
    }

    @objc private func showSettings() { show() }

    private func makeMainMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Browser Picker", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settings = appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Browser Picker", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Browser Picker", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let main = NSMenu()
        for (title, submenu) in [("Browser Picker", appMenu), ("Window", windowMenu)] {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            main.addItem(item)
        }
        return main
    }
}
