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
        #expect(ProfileSource.forBundleID("com.apple.Safari") == nil)
        #expect(ProfileSource.forBundleID("org.mozilla.firefox")?.stateFile == "Firefox/profiles.ini")
        #expect(ProfileSource.forBundleID("org.mozilla.firefoxdeveloperedition") == nil)
        #expect(ProfileSource.forBundleID("org.mozilla.nightly") == nil)
    }
}

struct FirefoxProfilesTests {
    private func parse(_ ini: String, groups: [String: [ProfileGroupEntry]] = [:], asked: ((String) -> Void)? = nil) -> [BrowserProfile]? {
        FirefoxProfiles.parse(Data(ini.utf8)) { storeID in
            asked?(storeID)
            return groups[storeID]
        }
    }

    @Test func parsesClassicProfiles() throws {
        let profiles = try #require(parse("""
        [General]\r
        StartWithLastProfile=1\r
        \r
        ; comment\r
        # another\r
        [Profile1]\r
        Name=Work\r
        IsRelative=0\r
        Path=/Volumes/Data/ff/w0rk.Work\r
        \r
        [Profile0]\r
        Name = Personal \r
        IsRelative=1\r
        Path=Profiles/abcd1234.default-release\r
        Default=1\r
        [Install8216C80C92C4E828]\r
        Default=Profiles/abcd1234.default-release\r
        [BackgroundTasksProfiles]\r
        MozillaBackgroundTask-1=xyz.Background\r
        """))
        #expect(profiles.map(\.id) == ["/Volumes/Data/ff/w0rk.Work", "Profiles/abcd1234.default-release"])
        #expect(profiles.map(\.name) == ["Work", "Personal"])
        #expect(profiles.map(\.disambiguator) == ["w0rk.Work", "abcd1234.default-release"])
    }
    @Test func skipsIncompleteSections() {
        let ini = """
        [Profile0]
        Name=No path
        [Profile1]
        Path=Profiles/noname
        [ProfileX]
        Name=Not a profile
        Path=Profiles/x
        [Profile2]
        Name=Ok
        Path=Profiles/ok
        """
        #expect(parse(ini)?.map(\.name) == ["Ok"])
    }
    @Test func groupReplacedByItsProfiles() throws {
        var asked: [String] = []
        let profiles = try #require(parse("""
        [Profile0]
        Name=Original profile
        IsRelative=1
        Path=Profiles/aaa.Work
        StoreID=abc
        ShowSelector=0
        [Profile1]
        Name=Testing
        IsRelative=1
        Path=Profiles/ttt.Testing
        """, groups: ["abc": [
            ProfileGroupEntry(path: "Profiles/bbb.Personal", name: "Personal"),
            ProfileGroupEntry(path: "Profiles/aaa.Work", name: "Work"),
            ProfileGroupEntry(path: "Profiles/aaa.Work", name: "Work"),
            ProfileGroupEntry(path: "Profiles/ccc", name: ""),
        ]], asked: { asked.append($0) }))
        #expect(asked == ["abc"])
        #expect(profiles.map(\.name) == ["Personal", "Work", "Testing"])
        #expect(profiles.map(\.id) == ["Profiles/bbb.Personal", "Profiles/aaa.Work", "Profiles/ttt.Testing"])
    }
    @Test func unreadableGroupKeepsItsSection() {
        let ini = """
        [Profile0]
        Name=Original profile
        Path=Profiles/aaa.Work
        IsRelative=1
        StoreID=abc
        """
        for groups in [[:], ["abc": []]] as [[String: [ProfileGroupEntry]]] {
            #expect(parse(ini, groups: groups)?.map(\.id) == ["Profiles/aaa.Work"])
        }
    }
    @Test func malformedOrEmptyIsNil() {
        #expect(FirefoxProfiles.parse(Data([0xFF, 0xFE, 0x00]), group: { _ in nil }) == nil)
        #expect(parse("") == nil)
        #expect(parse("[General]\nStartWithLastProfile=1\n") == nil)
    }
}

struct FirefoxCatalogTests {
    struct Locator: ApplicationLocating {
        var ini: String?
        var ids = ["org.mozilla.firefox", "com.apple.Safari"]
        func bundleIDs(forOpening url: URL) -> [String] { ids }
        func canonicalURL(forBundleID id: String) -> URL? {
            switch id {
            case "org.mozilla.firefox": url("file:///Applications/Firefox.app")
            case "org.mozilla.firefoxdeveloperedition": url("file:///Applications/Firefox%20Developer%20Edition.app")
            default: url("file:///Applications/Safari.app")
            }
        }
        func displayName(at appURL: URL) -> String { appURL.deletingPathExtension().lastPathComponent.removingPercentEncoding ?? "" }
        func profileState(forBundleID id: String) -> Data? { ini.map { Data($0.utf8) } }
        func profileGroup(forBundleID id: String, storeID: String) -> [ProfileGroupEntry]? {
            storeID == "abc" ? [ProfileGroupEntry(path: "Profiles/w.Work", name: "Work"), ProfileGroupEntry(path: "Profiles/p.Personal", name: "Personal")] : nil
        }
    }
    static func ini(_ profiles: [(String, String)]) -> String {
        profiles.enumerated().map { "[Profile\($0)]\nName=\($1.1)\nIsRelative=1\nPath=\($1.0)\n" }.joined()
    }
    private func targets(_ ini: String?, ids: [String]? = nil) -> [BrowserTarget] {
        var locator = Locator(ini: ini)
        if let ids { locator.ids = ids }
        return BrowserCatalog(locator: locator, ownBundleID: nil).targets()
    }

    @Test func profilesBecomeRows() {
        let list = targets("[Profile0]\nName=Group\nPath=Profiles/w.Work\nIsRelative=1\nStoreID=abc\n")
        #expect(list.map(\.label) == ["Firefox — Personal", "Firefox — Work", "Safari"])
        #expect(list.map { $0.profile?.id } == ["Profiles/p.Personal", "Profiles/w.Work", nil])
    }
    @Test func singleProfileKeepsPlainLabelButCarriesProfile() {
        let firefox = targets(Self.ini([("Profiles/a.default-release", "default-release")]))[0]
        #expect(firefox.label == "Firefox")
        #expect(firefox.profile?.id == "Profiles/a.default-release")
    }
    @Test func duplicateNamesGetFolder() {
        let list = targets(Self.ini([("Profiles/e5f6g7h8.Work", "Work"), ("Profiles/a1b2c3d4.Work", "Work")]))
        #expect(list.prefix(2).map(\.label) == ["Firefox — Work (a1b2c3d4.Work)", "Firefox — Work (e5f6g7h8.Work)"])
    }
    @Test func unreadableFallsBack() {
        let firefox = targets(nil)[0]
        #expect(firefox.label == "Firefox")
        #expect(firefox.profile == nil)
    }
    @Test func developerEditionStaysOneRow() {
        let list = targets(Self.ini([("Profiles/a", "A"), ("Profiles/b", "B")]), ids: ["org.mozilla.firefoxdeveloperedition"])
        #expect(list.map(\.label) == ["Firefox Developer Edition"])
        #expect(list[0].profile == nil)
    }

    @Test func profileRuleRouting() throws {
        let list = targets(Self.ini([("Profiles/p.Personal", "Personal"), ("Profiles/w.Work", "Work")]))
        let work = try #require(list.first { $0.profile?.id == "Profiles/w.Work" })
        let rules = RuleSet([DomainRule(domain: "github.com", target: work)])
        let link = url("https://github.com/x")
        #expect(LinkRouter.route(link, overrideHeld: false, rules: rules, targets: list) == .open(work))
        let withoutWork = targets(Self.ini([("Profiles/p.Personal", "Personal"), ("Profiles/j.Job", "Job")]))
        #expect(LinkRouter.route(link, overrideHeld: false, rules: rules, targets: withoutWork) == .showPicker(highlight: nil))
    }
    @Test func legacyRuleOpensDefaultProfile() {
        let list = targets(Self.ini([("Profiles/p.Personal", "Personal"), ("Profiles/w.Work", "Work")]))
        let rules = RuleSet([DomainRule(domain: "github.com", bundleID: Fix.firefox.id, browserName: "Firefox")])
        #expect(LinkRouter.route(url("https://github.com/x"), overrideHeld: false, rules: rules, targets: list)
            == .open(BrowserTarget(browser: Fix.firefox, label: "Firefox (default profile)")))
    }
}

struct HiddenArcTests {
    static let arcID = "company.thebrowser.Browser"
    struct Locator: ApplicationLocating {
        var ids = [HiddenArcTests.arcID, "com.apple.Safari"]
        func bundleIDs(forOpening url: URL) -> [String] { ids }
        func canonicalURL(forBundleID id: String) -> URL? { url("file:///Applications/\(id == "com.apple.Safari" ? "Safari" : "Arc").app") }
        func displayName(at appURL: URL) -> String { appURL.deletingPathExtension().lastPathComponent }
        func profileState(forBundleID id: String) -> Data? { nil }
    }
    let link = url("https://github.com/x")

    @Test func arcIsNotListed() {
        #expect(BrowserCatalog(locator: Locator(), ownBundleID: nil).targets().map(\.label) == ["Safari"])
    }
    @Test func onlyArcMeansNoBrowsers() {
        #expect(BrowserCatalog(locator: Locator(ids: [Self.arcID]), ownBundleID: nil).targets().isEmpty)
    }
    @Test func arcRulesShowPicker() {
        let targets = BrowserCatalog(locator: Locator(), ownBundleID: nil).targets()
        for profileID in [nil, "S1"] {
            let rules = RuleSet([DomainRule(domain: "github.com", bundleID: Self.arcID, browserName: "Arc", profileID: profileID, profileName: profileID.map { _ in "Pro" })])
            #expect(LinkRouter.route(link, overrideHeld: false, rules: rules, targets: targets) == .showPicker(highlight: nil))
            #expect(LinkRouter.route(link, overrideHeld: true, rules: rules, targets: targets) == .showPicker(highlight: nil))
        }
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
            // Safari is "blocked" too, but has no profile source, so it is not listed. Arc is hidden.
            func isProfileStateBlocked(forBundleID id: String) -> Bool { true }
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
