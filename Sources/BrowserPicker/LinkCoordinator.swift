import AppKit
import BrowserPickerCore

@MainActor
final class LinkCoordinator {
    private let ruleStore: RuleStore
    private let catalog: BrowserCatalog
    private var queue = LinkQueue()
    private var panel: PickerPanel?

    init(ruleStore: RuleStore, catalog: BrowserCatalog) {
        self.ruleStore = ruleStore
        self.catalog = catalog
    }

    func enqueue(_ urls: [URL], overrideHeld: Bool) {
        for url in urls { queue.enqueue(PendingLink(url: url, overrideHeld: overrideHeld)) }
        drain()
    }

    /// Opens ruled links directly; stops at the first link that needs a picker.
    private func drain() {
        while queue.count > 0, !queue.pickerActive {
            let browsers = catalog.browsers()
            guard let (link, decision) = queue.next(rules: ruleStore.ruleSet, browsers: browsers) else { return }
            switch decision {
            case .open(let browser):
                launch(link.url, in: browser)
            case .showPicker(let highlight):
                showPicker(for: link.url, browsers: browsers, highlight: highlight)
                return
            }
        }
    }

    private func launch(_ url: URL, in browser: Browser) {
        BrowserLauncher.open(url, in: browser) { [weak self] in
            guard let self else { return }
            self.queue.pushFront(PendingLink(url: url, forcePicker: true))
            self.drain()
        }
    }

    private func showPicker(for url: URL, browsers: [Browser], highlight: Browser.ID?) {
        let model = PickerModel(url: url, browsers: browsers, highlight: highlight)
        let panel = PickerPanel(model: model) { [weak self] action in
            self?.resolve(action, model: model)
        }
        self.panel = panel
        panel.present(at: NSEvent.mouseLocation)
    }

    private func resolve(_ action: PickerAction, model: PickerModel) {
        panel?.dismiss()
        panel = nil
        switch action {
        case .choose(let browser, let remember):
            if remember, let domain = model.domain {
                ruleStore.save(domain: domain, browser: browser)
            }
            launch(model.url, in: browser)
        case .cancel:
            // Hand focus back to the source app, unless the user is working in Settings.
            let hasOtherWindow = NSApp.windows.contains { $0.isVisible && !($0 is NSPanel) }
            if NSApp.isActive, !hasOtherWindow { NSApp.hide(nil) }
        case .none:
            break
        }
        queue.pickerResolved()
        drain()
    }
}
