import Foundation
import Observation

/// Persists domain rules as versioned JSON in `UserDefaults`.
@MainActor
@Observable
public final class RuleStore {
    public static let defaultsKey = "domainRules"

    private struct Payload: Codable {
        var version: Int
        var rules: [DomainRule]
    }

    @ObservationIgnored private let defaults: UserDefaults
    public private(set) var ruleSet: RuleSet

    public var rules: [DomainRule] { ruleSet.rules }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let payload = try? Self.decoder.decode(Payload.self, from: data) {
            ruleSet = RuleSet(payload.rules)
        } else {
            ruleSet = RuleSet()
        }
    }

    /// Saves a rule, replacing any existing rule for the same domain.
    public func save(domain: String, browser: Browser) {
        let rule = DomainRule(domain: domain, bundleID: browser.id, browserName: browser.name)
        ruleSet = ruleSet.saving(rule)
        persist()
    }

    public func changeBrowser(domain: String, to browser: Browser) {
        guard ruleSet.rule(forDomain: domain) != nil else { return }
        save(domain: domain, browser: browser)
    }

    public func delete(domain: String) {
        ruleSet = ruleSet.removing(domain: domain)
        persist()
    }

    public func removeAll() {
        ruleSet = RuleSet()
        persist()
    }

    private func persist() {
        let payload = Payload(version: 1, rules: ruleSet.rules)
        if let data = try? Self.encoder.encode(payload) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
