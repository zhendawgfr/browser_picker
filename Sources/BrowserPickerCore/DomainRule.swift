import Foundation

public struct DomainRule: Codable, Hashable, Sendable {
    public var domain: String
    public var bundleID: String
    /// Snapshot of the browser's name so Settings can label a rule whose browser is gone.
    public var browserName: String
    public var savedAt: Date
    /// Profile folder name, for rules saved against a Chromium profile. `nil` means the browser's last-used profile.
    public var profileID: String?
    /// Snapshot of the profile's name so Settings can label a rule whose profile is gone.
    public var profileName: String?

    public init(domain: String, bundleID: String, browserName: String, savedAt: Date = Date(),
                profileID: String? = nil, profileName: String? = nil) {
        self.domain = domain
        self.bundleID = bundleID
        self.browserName = browserName
        self.savedAt = savedAt
        self.profileID = profileID
        self.profileName = profileName
    }

    public init(domain: String, target: BrowserTarget, savedAt: Date = Date()) {
        self.init(domain: domain, bundleID: target.browser.id, browserName: target.browser.name, savedAt: savedAt,
                  profileID: target.profile?.id, profileName: target.profile?.name)
    }

    public var targetID: TargetID { TargetID(bundleID: bundleID, profileID: profileID) }

    /// Label from the saved snapshot, for when the rule's browser or profile cannot be resolved.
    public var snapshotLabel: String {
        profileName.map { "\(browserName) — \($0)" } ?? browserName
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

    /// Rule for exactly the link's domain. Subdomains are not covered, so each one can get its own rule.
    public func rule(for url: URL) -> DomainRule? {
        DomainKey.key(for: url).flatMap { byDomain[$0] }
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
