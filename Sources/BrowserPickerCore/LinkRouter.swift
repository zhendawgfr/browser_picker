import Foundation

public enum RouteDecision: Equatable, Sendable {
    case open(BrowserTarget)
    case showPicker(highlight: TargetID?)
}

public enum LinkRouter {
    public static func route(_ url: URL, overrideHeld: Bool, rules: RuleSet, targets: [BrowserTarget]) -> RouteDecision {
        let rule = rules.rule(for: url)
        if overrideHeld { return .showPicker(highlight: rule.flatMap { highlight(for: $0, in: targets) }) }
        if let rule, let target = resolve(rule, in: targets) { return .open(target) }
        return .showPicker(highlight: nil)
    }

    /// The target a rule opens, or `nil` when its browser or profile is not currently available.
    /// A rule with a profile only matches a profile that was just discovered, so a stale folder name
    /// can never be launched (Chromium would create a new empty profile for it).
    public static func resolve(_ rule: DomainRule, in targets: [BrowserTarget]) -> BrowserTarget? {
        if rule.profileID != nil { return targets.first { $0.id == rule.targetID } }
        let ofBrowser = targets.filter { $0.browser.id == rule.bundleID }
        guard let first = ofBrowser.first else { return nil }
        if let plain = ofBrowser.first(where: { $0.profile == nil }) { return plain }
        return ofBrowser.count > 1 ? .lastUsed(first.browser) : BrowserTarget(browser: first.browser)
    }

    /// Picker row to highlight for a rule: its profile, or the browser's first row for a rule without one.
    public static func highlight(for rule: DomainRule, in targets: [BrowserTarget]) -> TargetID? {
        if rule.profileID != nil { return targets.first { $0.id == rule.targetID }?.id }
        return targets.first { $0.browser.id == rule.bundleID }?.id
    }
}
