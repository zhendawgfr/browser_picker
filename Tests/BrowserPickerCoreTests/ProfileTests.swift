import Foundation
import Testing
@testable import BrowserPickerCore

private func localState(_ entries: String) -> Data {
    Data(#"{"profile":{"info_cache":{\#(entries)}},"other":1}"#.utf8)
}

struct ChromiumProfilesTests {
    @Test func parsesProfiles() throws {
        let data = localState(#"""
        "Default":{"name":"Personal"},
        "Profile 1":{"name":"work"},
        "Profile 2":{"name":"Hidden","is_omitted_from_profile_list":true},
        "Profile 3":{"name":""},
        "Profile 4":{"user_name":"x"}
        """#)
        let profiles = try #require(ChromiumProfiles.parse(data))
        #expect(profiles.map(\.id) == ["Default", "Profile 1"])
        #expect(profiles.map(\.name) == ["Personal", "work"])
        #expect(profiles.map(\.disambiguator) == ["Default", "Profile 1"])
    }
    @Test func malformedOrEmptyIsNil() {
        #expect(ChromiumProfiles.parse(Data("not json".utf8)) == nil)
        #expect(ChromiumProfiles.parse(localState("")) == nil)
        #expect(ChromiumProfiles.parse(Data(#"{"profile":{}}"#.utf8)) == nil)
    }
    @Test func table() {
        #expect(ProfileSource.forBundleID("com.brave.Browser") == .chromium("BraveSoftware/Brave-Browser"))
        #expect(ProfileSource.forBundleID("com.brave.Browser")?.stateFile == "BraveSoftware/Brave-Browser/Local State")
        #expect(ProfileSource.forBundleID("company.thebrowser.Browser")?.stateFile == "Arc/StorableSidebar.json")
        #expect(ProfileSource.forBundleID("com.apple.Safari") == nil)
    }
}

/// Trimmed shape of Arc's `StorableSidebar.json`: `spaces` alternates an ID and the Space object.
private func sidebar(_ titles: [String?]) -> Data {
    let spaces: [Any] = titles.enumerated().flatMap { i, title -> [Any] in
        var space: [String: Any] = ["id": "S\(i + 1)", "profile": ["default": true]]
        if let title { space["title"] = title }
        return ["S\(i + 1)", space]
    }
    let root: [String: Any] = ["sidebar": ["containers": [["global": [:]], ["spaces": spaces, "items": []]]], "version": 1]
    return try! JSONSerialization.data(withJSONObject: root)
}

struct ArcSpacesTests {
    @Test func parsesTitledSpacesInSidebarOrder() throws {
        let spaces = try #require(ArcSpaces.parse(sidebar(["Pro", "Perso", nil, ""])))
        #expect(spaces.map(\.name) == ["Pro", "Perso"])
        #expect(spaces.map(\.id) == ["S1", "S2"])
        #expect(spaces.map(\.disambiguator) == ["Space 1", "Space 2"])
    }
    @Test func malformedOrUntitledIsNil() {
        #expect(ArcSpaces.parse(Data("nope".utf8)) == nil)
        #expect(ArcSpaces.parse(sidebar([nil])) == nil)
        #expect(ArcSpaces.parse(Data(#"{"sidebar":{}}"#.utf8)) == nil)
    }
}

struct ArcCatalogTests {
    struct ArcLocator: ApplicationLocating {
        var sidebarData: Data?
        func bundleIDs(forOpening url: URL) -> [String] { ["company.thebrowser.Browser", "com.apple.Safari"] }
        func canonicalURL(forBundleID id: String) -> URL? { url("file:///Applications/\(id == "com.apple.Safari" ? "Safari" : "Arc").app") }
        func displayName(at appURL: URL) -> String { appURL.deletingPathExtension().lastPathComponent }
        func profileState(forBundleID id: String) -> Data? { id == "company.thebrowser.Browser" ? sidebarData : nil }
    }
    private func targets(_ titles: [String?]?) -> [BrowserTarget] {
        BrowserCatalog(locator: ArcLocator(sidebarData: titles.map(sidebar)), ownBundleID: nil).targets()
    }

    @Test func spacesBecomeRows() {
        let list = targets(["Pro", "Perso", nil])
        #expect(list.map(\.label) == ["Arc — Perso", "Arc — Pro", "Safari"])
        #expect(list.map { $0.profile?.id } == ["S2", "S1", nil])
    }
    @Test func singleSpaceIsPlainArc() {
        let arc = targets(["Perso"])[0]
        #expect(arc.label == "Arc")
        #expect(arc.profile == nil)
    }
    @Test func duplicateTitlesGetSpaceNumber() {
        #expect(targets(["Work", "Home", "Work"]).map(\.label) == ["Arc — Home", "Arc — Work (Space 1)", "Arc — Work (Space 3)", "Safari"])
    }
    @Test func unreadableSidebarFallsBack() {
        #expect(targets(nil).map(\.label) == ["Arc", "Safari"])
    }
}

struct ProfileCacheTests {
    final class CountingLocator: ApplicationLocating, @unchecked Sendable {
        var date = Date(timeIntervalSince1970: 1)
        var data = Data(#"{"profile":{"info_cache":{"Default":{"name":"A"},"Profile 1":{"name":"B"}}}}"#.utf8)
        var reads = 0
        func bundleIDs(forOpening url: URL) -> [String] { ["com.brave.Browser"] }
        func canonicalURL(forBundleID id: String) -> URL? { url("file:///Applications/Brave%20Browser.app") }
        func displayName(at appURL: URL) -> String { "Brave Browser" }
        func profileState(forBundleID id: String) -> Data? { reads += 1; return data }
        func profileStateDate(forBundleID id: String) -> Date? { date }
    }

    @Test func unchangedFileIsReadOnce() {
        let locator = CountingLocator()
        let catalog = BrowserCatalog(locator: locator, ownBundleID: nil)
        _ = catalog.targets()
        #expect(catalog.targets().map(\.label) == ["Brave Browser — A", "Brave Browser — B"])
        #expect(locator.reads == 1)
    }
    @Test func changedFileIsReadAgain() {
        let locator = CountingLocator()
        let catalog = BrowserCatalog(locator: locator, ownBundleID: nil)
        _ = catalog.targets()
        locator.data = Data(#"{"profile":{"info_cache":{"Default":{"name":"A"},"Profile 1":{"name":"Job"}}}}"#.utf8)
        locator.date = Date(timeIntervalSince1970: 2)
        #expect(catalog.targets().map(\.label) == ["Brave Browser — A", "Brave Browser — Job"])
        #expect(locator.reads == 2)
    }
    @Test func warmUpFillsCache() async throws {
        let locator = CountingLocator()
        let catalog = BrowserCatalog(locator: locator, ownBundleID: nil)
        catalog.warmUp()
        for _ in 0..<100 where locator.reads == 0 { try await Task.sleep(for: .milliseconds(10)) }
        _ = catalog.targets()
        #expect(locator.reads == 1)
    }
    @Test func failedReadIsRetried() {
        // Full Disk Access granted later: the file is unchanged, but must be read again.
        let locator = CountingLocator()
        let good = locator.data
        locator.data = Data()
        let catalog = BrowserCatalog(locator: locator, ownBundleID: nil)
        #expect(catalog.targets().map(\.label) == ["Brave Browser"])
        locator.data = good
        #expect(catalog.targets().map(\.label) == ["Brave Browser — A", "Brave Browser — B"])
    }
    @Test func blockedBrowsersListsOnlyProfileCapableBlocked() {
        struct Locator: ApplicationLocating {
            func bundleIDs(forOpening url: URL) -> [String] { ["com.brave.Browser", "com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser"] }
            func canonicalURL(forBundleID id: String) -> URL? { url("file:///Applications/\(id).app") }
            func displayName(at appURL: URL) -> String { appURL.deletingPathExtension().lastPathComponent }
            func profileState(forBundleID id: String) -> Data? { nil }
            // Safari is "blocked" too, but has no profile source, so it is not listed.
            func isProfileStateBlocked(forBundleID id: String) -> Bool { id != "company.thebrowser.Browser" }
        }
        let blocked = BrowserCatalog(locator: Locator(), ownBundleID: nil).blockedBrowsers()
        #expect(blocked.map(\.id) == ["com.brave.Browser", "com.google.Chrome"])
    }
    @Test func unknownDateIsNeverCached() {
        let locator = CountingLocator()
        let catalog = BrowserCatalog(locator: CountingLocatorNoDate(inner: locator), ownBundleID: nil)
        _ = catalog.targets(); _ = catalog.targets()
        #expect(locator.reads == 2)
    }
    struct CountingLocatorNoDate: ApplicationLocating {
        let inner: CountingLocator
        func bundleIDs(forOpening url: URL) -> [String] { inner.bundleIDs(forOpening: url) }
        func canonicalURL(forBundleID id: String) -> URL? { inner.canonicalURL(forBundleID: id) }
        func displayName(at appURL: URL) -> String { inner.displayName(at: appURL) }
        func profileState(forBundleID id: String) -> Data? { inner.profileState(forBundleID: id) }
    }
}

struct ProfileCatalogTests {
    private func catalog(_ braveEntries: String?) -> BrowserCatalog {
        var locator = BrowserCatalogTests.FakeLocator()
        if let braveEntries { locator.states["com.brave.Browser"] = localState(braveEntries) }
        // A Local State for a browser outside the table must be ignored.
        locator.states["com.apple.Safari"] = localState(#""A":{"name":"x"},"B":{"name":"y"}"#)
        return BrowserCatalog(locator: locator, ownBundleID: "dev.test.Picker")
    }

    @Test func expandsProfilesSortedAndGrouped() {
        let list = catalog(#""Default":{"name":"work"},"Profile 1":{"name":"Personal"}"#).targets()
        #expect(list.map(\.label) == ["Brave Browser — Personal", "Brave Browser — work", "Firefox", "Safari"])
        #expect(list.map { $0.profile?.id } == ["Profile 1", "Default", nil, nil])
        #expect(list.filter { $0.browser.id == "com.brave.Browser" }.count == 2) // Sparkle duplicate expands once
    }
    @Test func singleProfileKeepsPlainLabelButCarriesProfile() {
        let brave = catalog(#""Default":{"name":"Personal"}"#).targets()[0]
        #expect(brave.label == "Brave Browser")
        #expect(brave.profile?.id == "Default")
    }
    @Test func duplicateNamesGetFolder() {
        let list = catalog(#""Default":{"name":"Person 1"},"Profile 2":{"name":"Person 1"}"#).targets()
        #expect(list.prefix(2).map(\.label) == ["Brave Browser — Person 1 (Default)", "Brave Browser — Person 1 (Profile 2)"])
    }
    @Test func unreadableFallsBack() {
        for c in [catalog(nil), catalog("")] {
            let brave = c.targets()[0]
            #expect(brave.label == "Brave Browser")
            #expect(brave.profile == nil)
        }
    }
}

@MainActor
struct ProfileRuleTests {
    @Test func legacyJSONLoadsWithoutProfile() throws {
        let d = Fix.freshDefaults()
        let json = #"{"version":1,"rules":[{"domain":"a.com","bundleID":"com.brave.Browser","browserName":"Brave Browser","savedAt":"2026-01-01T00:00:00Z"}]}"#
        d.set(Data(json.utf8), forKey: RuleStore.defaultsKey)
        let rule = try #require(RuleStore(defaults: d).rules.first)
        #expect(rule.profileID == nil && rule.profileName == nil)
    }
    @Test func profileRuleRoundTripsAndReplaces() {
        let d = Fix.freshDefaults()
        let store = RuleStore(defaults: d)
        store.save(domain: "a.com", target: Fix.tPersonal)
        #expect(RuleStore(defaults: d).rules.first?.profileID == "Default")
        #expect(RuleStore(defaults: d).rules.first?.profileName == "Personal")
        store.change(domain: "a.com", to: Fix.tWork)
        #expect(store.rules.count == 1)
        #expect(RuleStore(defaults: d).rules.first?.profileID == "Profile 1")
    }
    @Test func olderBuildCanDecodeNewJSON() throws {
        struct OldRule: Codable { var domain: String; var bundleID: String; var browserName: String; var savedAt: Date }
        struct OldPayload: Codable { var version: Int; var rules: [OldRule] }
        let d = Fix.freshDefaults()
        RuleStore(defaults: d).save(domain: "a.com", target: Fix.tWork)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let old = try decoder.decode(OldPayload.self, from: #require(d.data(forKey: RuleStore.defaultsKey)))
        #expect(old.rules.first?.bundleID == "com.brave.Browser")
    }
}

struct ProfileRouterTests {
    let profileRule = RuleSet([DomainRule(domain: "github.com", target: Fix.tWork)])
    let legacyRule = RuleSet([DomainRule(domain: "github.com", bundleID: Fix.brave.id, browserName: "Brave Browser")])
    let link = url("https://github.com/x")

    @Test func profileRuleMatches() {
        #expect(LinkRouter.route(link, overrideHeld: false, rules: profileRule, targets: Fix.profileTargets) == .open(Fix.tWork))
    }
    @Test func deletedProfileShowsPicker() {
        let targets = [Fix.tPersonal, Fix.tSafari]
        #expect(LinkRouter.route(link, overrideHeld: false, rules: profileRule, targets: targets) == .showPicker(highlight: nil))
    }
    @Test func unreadableProfileListShowsPicker() {
        let targets = [Fix.tBrave, Fix.tSafari]
        #expect(LinkRouter.route(link, overrideHeld: false, rules: profileRule, targets: targets) == .showPicker(highlight: nil))
    }
    @Test func missingBrowserShowsPicker() {
        #expect(LinkRouter.route(link, overrideHeld: false, rules: profileRule, targets: [Fix.tSafari]) == .showPicker(highlight: nil))
    }
    @Test func legacyRuleOpensLastUsedProfile() {
        guard case .open(let target) = LinkRouter.route(link, overrideHeld: false, rules: legacyRule, targets: Fix.profileTargets) else {
            Issue.record("expected .open"); return
        }
        #expect(target.profile == nil)
        #expect(target.browser == Fix.brave)
        #expect(target.label == "Brave Browser (last used profile)")
    }
    @Test func legacyArcRuleOpensCurrentSpace() {
        let arc = Browser(id: "company.thebrowser.Browser", name: "Arc", appURL: url("file:///Applications/Arc.app"))
        let spaces = [BrowserProfile(id: "S1", name: "Perso"), BrowserProfile(id: "S2", name: "Pro")]
            .map { BrowserTarget(browser: arc, profile: $0, label: "Arc — \($0.name)") }
        let rules = RuleSet([DomainRule(domain: "github.com", bundleID: arc.id, browserName: "Arc")])
        #expect(LinkRouter.route(link, overrideHeld: false, rules: rules, targets: spaces) == .open(BrowserTarget(browser: arc, label: "Arc (current Space)")))
    }
    @Test func overrideHighlightsProfile() {
        #expect(LinkRouter.route(link, overrideHeld: true, rules: profileRule, targets: Fix.profileTargets) == .showPicker(highlight: Fix.tWork.id))
    }
    @Test func overrideWithLegacyRuleHighlightsFirstOfBrowser() {
        #expect(LinkRouter.route(link, overrideHeld: true, rules: legacyRule, targets: Fix.profileTargets) == .showPicker(highlight: Fix.tPersonal.id))
    }
}

@MainActor
struct ProfilePickerTests {
    @Test func numberKeyChoosesProfile() {
        let m = PickerModel(url: url("https://github.com/x"), targets: Fix.profileTargets)
        #expect(m.handle(.digit(2)) == .choose(Fix.tWork, remember: false))
    }
    @Test func rememberReturnsProfileTarget() {
        let m = PickerModel(url: url("https://github.com/x"), targets: Fix.profileTargets)
        _ = m.handle(.character("r"))
        #expect(m.handle(.digit(2)) == .choose(Fix.tWork, remember: true))
    }
    @Test func highlightByProfile() {
        let m = PickerModel(url: url("https://github.com/x"), targets: Fix.profileTargets, highlight: Fix.tWork.id)
        #expect(m.highlightIndex == 1)
    }
}
