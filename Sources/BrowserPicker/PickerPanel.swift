import AppKit
import BrowserPickerCore
import SwiftUI

@MainActor
final class PickerPanel: NSPanel, NSWindowDelegate {
    private let model: PickerModel
    private let onAction: (PickerAction) -> Void
    private var finished = false

    init(model: PickerModel, onAction: @escaping (PickerAction) -> Void) {
        self.model = model
        self.onAction = onAction
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)

        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        delegate = self

        let host = NSHostingView(rootView: PickerView(model: model) { [weak self] index in
            guard let self else { return }
            self.finish(self.model.choose(index: index))
        })
        let size = host.fittingSize
        host.frame = CGRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]

        let effect = NSVisualEffectView(frame: host.frame)
        effect.material = .popover
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.addSubview(host)
        contentView = effect
        setContentSize(size)
    }

    override var canBecomeKey: Bool { true }

    /// Shows the panel near `cursor` on the screen that contains it.
    func present(at cursor: CGPoint) {
        let screen = NSScreen.screens.first { NSMouseInRect(cursor, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            setFrame(PanelPlacement.frame(size: frame.size, cursor: cursor, screenVisibleFrame: visible), display: false)
        }
        // An inactive app's panel gets no key events, so activate; cancelling hands focus back via NSApp.hide.
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        delegate = nil
        orderOut(nil)
    }

    // Handle keys before the responder chain so the SwiftUI controls can't swallow them.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, let key = Self.pickerKey(for: event) {
            finish(model.handle(key))
            return
        }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) {
        finish(.cancel)
    }

    func windowDidResignKey(_ notification: Notification) {
        finish(.cancel)
    }

    private func finish(_ action: PickerAction) {
        guard action != .none, !finished else { return }
        finished = true
        onAction(action)
    }

    private static let digitKeyCodes: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9, // number row
        83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9, // keypad
    ]

    private static func pickerKey(for event: NSEvent) -> PickerKey? {
        switch event.keyCode {
        case 53: return .escape
        case 126: return .up
        case 125: return .down
        case 36, 76: return .confirm
        case 15 where event.modifierFlags.intersection([.command, .control]).isEmpty:
            return .character("r") // physical R key, whatever the keyboard layout
        default: break
        }
        guard event.modifierFlags.intersection([.command, .control]).isEmpty else { return nil }
        // Number keys by physical position: on AZERTY the digit row types symbols without Shift.
        if let n = digitKeyCodes[event.keyCode] { return .digit(n) }
        guard let c = event.charactersIgnoringModifiers?.first else { return nil }
        if let n = c.wholeNumberValue, c.isASCII { return .digit(n) }
        return .character(c)
    }
}
