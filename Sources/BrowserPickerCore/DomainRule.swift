import Foundation

public struct DomainRule: Codable, Hashable, Sendable {
    public var domain: String
    public var bundleID: String
    /// Snapshot of the browser's name so Settings can label a rule whose browser is gone.
    public var browserName: String
    public var savedAt: Date

    public init(domain: String, bundleID: String, browserName: String, savedAt: Date = Date()) {
        self.domain = domain
        self.bundleID = bundleID
        self.browserName = browserName
        self.savedAt = savedAt
    }
}

public struct RuleSet: Sendable, Equatable {
    private var byDomain: [String: DomainRule]

    public init(_ rules: [DomainRule] = []) {
        byDomain = Dictionary(rules.map { ($0.domain, $0) }, uniquingKeysWith: { _, new in new })
    }

    public var rules: [DomainRule] {
        byDomain.values.sorted { $0.domain < $1.domain }
    }

    public func rule(forDomain domain: String) -> DomainRule? {
        byDomain[domain]
    }

    /// Most specific rule covering the link: the longest matching domain on label boundaries.
    /// IP literals match only a rule for exactly the same address.
    public func rule(for url: URL) -> DomainRule? {
        guard let domain = DomainKey.key(for: url) else { return nil }
        if DomainKey.isIPAddress(domain) { return byDomain[domain] }
        for suffix in DomainKey.suffixes(of: domain) {
            if let rule = byDomain[suffix] { return rule }
        }
        return nil
    }

    public func saving(_ rule: DomainRule) -> RuleSet {
        var copy = self
        copy.byDomain[rule.domain] = rule
        return copy
    }

    public func removing(domain: String) -> RuleSet {
        var copy = self
        copy.byDomain[domain] = nil
        return copy
    }
}
