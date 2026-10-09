import Foundation

public enum RouteDecision: Equatable, Sendable {
    case open(Browser)
    case showPicker(highlight: Browser.ID?)
}

public enum LinkRouter {
    public static func route(_ url: URL, overrideHeld: Bool, rules: RuleSet, browsers: [Browser]) -> RouteDecision {
        let browser = rules.rule(for: url).flatMap { rule in browsers.first { $0.id == rule.bundleID } }
        if overrideHeld { return .showPicker(highlight: browser?.id) }
        if let browser { return .open(browser) }
        return .showPicker(highlight: nil)
    }
}
