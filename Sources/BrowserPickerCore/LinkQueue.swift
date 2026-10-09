import Foundation

public struct PendingLink: Equatable, Sendable {
    public var url: URL
    public var overrideHeld: Bool
    /// Show the picker regardless of rules (retry after a failed open).
    public var forcePicker: Bool

    public init(url: URL, overrideHeld: Bool = false, forcePicker: Bool = false) {
        self.url = url
        self.overrideHeld = overrideHeld
        self.forcePicker = forcePicker
    }
}

/// FIFO of incoming links. At most one picker is active; links are routed when dequeued.
public struct LinkQueue: Sendable {
    private var pending: [PendingLink] = []
    public private(set) var pickerActive = false

    public init() {}

    public var count: Int { pending.count }

    public mutating func enqueue(_ link: PendingLink) {
        pending.append(link)
    }

    public mutating func pushFront(_ link: PendingLink) {
        pending.insert(link, at: 0)
    }

    /// Next link and its routing decision, or `nil` when empty or a picker is still open.
    /// A `.showPicker` decision marks the picker active until `pickerResolved()`.
    public mutating func next(rules: RuleSet, targets: [BrowserTarget]) -> (link: PendingLink, decision: RouteDecision)? {
        guard !pickerActive, !pending.isEmpty else { return nil }
        let link = pending.removeFirst()
        let decision: RouteDecision = link.forcePicker
            ? .showPicker(highlight: nil)
            : LinkRouter.route(link.url, overrideHeld: link.overrideHeld, rules: rules, targets: targets)
        if case .showPicker = decision { pickerActive = true }
        return (link, decision)
    }

    public mutating func pickerResolved() {
        pickerActive = false
    }
}
