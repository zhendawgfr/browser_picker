import Foundation
import Testing
@testable import BrowserPickerCore

struct DomainKeyTests {
    @Test func normalizesCaseWwwAndPort() {
        #expect(DomainKey.key(for: url("https://WWW.GitHub.com:443/a?b=c")) == "github.com")
    }
    @Test func wwwComUnchanged() {
        #expect(DomainKey.key(for: url("https://www.com/")) == "www.com")
    }
    @Test func schemeEquivalence() {
        #expect(DomainKey.key(for: url("http://example.com/")) == DomainKey.key(for: url("https://example.com/")))
    }
    @Test func hostlessIsNil() {
        #expect(DomainKey.key(for: url("mailto:a@b.com")) == nil)
        #expect(DomainKey.key(for: url("https:///path")) == nil)
    }
    @Test func ipv6Host() {
        #expect(DomainKey.key(for: url("http://[::1]:8080/x")) == "::1")
        #expect(DomainKey.isIPAddress("::1"))
        #expect(DomainKey.isIPAddress("10.0.0.1"))
        #expect(!DomainKey.isIPAddress("github.com"))
    }
    @Test func suffixes() {
        #expect(DomainKey.suffixes(of: "a.b.c.com") == ["a.b.c.com", "b.c.com", "c.com", "com"])
    }
}

struct RuleSetTests {
    private func rule(_ d: String, _ b: Browser) -> DomainRule {
        DomainRule(domain: d, bundleID: b.id, browserName: b.name)
    }
    @Test func subdomainCovered() {
        let rs = RuleSet([rule("google.com", Fix.brave)])
        #expect(rs.rule(for: url("https://docs.google.com/x"))?.bundleID == Fix.brave.id)
    }
    @Test func mostSpecificWins() {
        let rs = RuleSet([rule("google.com", Fix.brave), rule("docs.google.com", Fix.safari)])
        #expect(rs.rule(for: url("https://docs.google.com/x"))?.bundleID == Fix.safari.id)
        #expect(rs.rule(for: url("https://mail.google.com/x"))?.bundleID == Fix.brave.id)
    }
    @Test func noPartialLabelMatch() {
        let rs = RuleSet([rule("hub.com", Fix.brave)])
        #expect(rs.rule(for: url("https://github.com/")) == nil)
    }
    @Test func ipExactOnly() {
        let rs = RuleSet([rule("10.0.0.1", Fix.safari)])
        #expect(rs.rule(for: url("http://10.0.0.1:8080/")) != nil)
        #expect(rs.rule(for: url("http://110.0.0.1/")) == nil)
    }
    @Test func schemeDoesNotMatter() {
        let rs = RuleSet([rule("example.com", Fix.safari)])
        #expect(rs.rule(for: url("http://example.com/")) != nil)
    }
}

@MainActor
struct RuleStoreTests {
    @Test func survivesNewInstance() {
        let d = Fix.freshDefaults()
        RuleStore(defaults: d).save(domain: "github.com", browser: Fix.brave)
        let again = RuleStore(defaults: d)
        #expect(again.rules.map(\.domain) == ["github.com"])
        #expect(again.rules.first?.browserName == "Brave Browser")
        #expect(again.ruleSet.rule(for: url("https://github.com/x"))?.bundleID == Fix.brave.id)
    }
    @Test func savingReplaces() {
        let store = RuleStore(defaults: Fix.freshDefaults())
        store.save(domain: "github.com", browser: Fix.brave)
        store.save(domain: "github.com", browser: Fix.safari)
        #expect(store.rules.count == 1)
        #expect(store.rules.first?.bundleID == Fix.safari.id)
    }
    @Test func changeAndDelete() {
        let d = Fix.freshDefaults()
        let store = RuleStore(defaults: d)
        store.save(domain: "a.com", browser: Fix.brave)
        store.save(domain: "b.com", browser: Fix.brave)
        store.changeBrowser(domain: "a.com", to: Fix.safari)
        store.changeBrowser(domain: "nope.com", to: Fix.safari)
        store.delete(domain: "b.com")
        let again = RuleStore(defaults: d)
        #expect(again.rules.map(\.domain) == ["a.com"])
        #expect(again.rules.first?.bundleID == Fix.safari.id)
    }
    @Test func removeAllEmpties() {
        let d = Fix.freshDefaults()
        let store = RuleStore(defaults: d)
        store.save(domain: "a.com", browser: Fix.brave)
        store.removeAll()
        #expect(store.rules.isEmpty)
        #expect(RuleStore(defaults: d).rules.isEmpty)
    }
    @Test func storesVersionedJSON() throws {
        let d = Fix.freshDefaults()
        RuleStore(defaults: d).save(domain: "a.com", browser: Fix.brave)
        let data = try #require(d.data(forKey: "domainRules"))
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(obj["version"] as? Int == 1)
    }
}
