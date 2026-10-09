import Foundation
import Testing
@testable import BrowserPickerCore

struct BrowserCatalogTests {
    struct FakeLocator: ApplicationLocating {
        func bundleIDs(forOpening url: URL) -> [String] {
            // Observed on a real machine: Brave twice (one from Sparkle cache), Safari via Cryptex.
            ["com.brave.Browser", "com.apple.Safari", "com.brave.Browser", "org.mozilla.firefox", "dev.test.Picker"]
        }
        func canonicalURL(forBundleID id: String) -> URL? {
            switch id {
            case "com.brave.Browser": return url("file:///Applications/Brave%20Browser.app")
            case "com.apple.Safari": return url("file:///System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app")
            case "org.mozilla.firefox": return url("file:///Applications/Firefox.app")
            default: return url("file:///Users/x/Applications/Browser%20Picker.app")
            }
        }
        func displayName(at appURL: URL) -> String {
            appURL.deletingPathExtension().lastPathComponent.removingPercentEncoding ?? ""
        }
    }

    @Test func dedupesExcludesSelfAndSorts() {
        let list = BrowserCatalog(locator: FakeLocator(), ownBundleID: "dev.test.Picker").browsers()
        #expect(list.map(\.name) == ["Brave Browser", "Firefox", "Safari"])
        #expect(list[0].appURL.path == "/Applications/Brave Browser.app")
        #expect(list[2].appURL.path.contains("Cryptexes"))
    }
}

struct LinkRouterTests {
    let rules = RuleSet([DomainRule(domain: "github.com", bundleID: Fix.safari.id, browserName: "Safari")])

    @Test func ruleMatchOpens() {
        #expect(LinkRouter.route(url("https://github.com/x"), overrideHeld: false, rules: rules, browsers: Fix.all) == .open(Fix.safari))
    }
    @Test func noRuleShowsPicker() {
        #expect(LinkRouter.route(url("https://example.com"), overrideHeld: false, rules: rules, browsers: Fix.all) == .showPicker(highlight: nil))
    }
    @Test func missingBrowserShowsPicker() {
        let r = RuleSet([DomainRule(domain: "github.com", bundleID: "gone.Browser", browserName: "Gone")])
        #expect(LinkRouter.route(url("https://github.com"), overrideHeld: false, rules: r, browsers: Fix.all) == .showPicker(highlight: nil))
    }
    @Test func overrideHighlightsRemembered() {
        #expect(LinkRouter.route(url("https://github.com"), overrideHeld: true, rules: rules, browsers: Fix.all) == .showPicker(highlight: Fix.safari.id))
    }
    @Test func overrideWithMissingBrowserHasNoHighlight() {
        let r = RuleSet([DomainRule(domain: "github.com", bundleID: "gone.Browser", browserName: "Gone")])
        #expect(LinkRouter.route(url("https://github.com"), overrideHeld: true, rules: r, browsers: Fix.all) == .showPicker(highlight: nil))
    }
}

struct LinkQueueTests {
    @Test func burstShownInOrder() {
        var q = LinkQueue()
        for u in ["https://a.com", "https://b.com", "https://c.com"] { q.enqueue(PendingLink(url: url(u))) }
        var seen: [String] = []
        for _ in 0..<3 {
            let n = q.next(rules: RuleSet(), browsers: Fix.all)
            #expect(n != nil)
            seen.append(n!.link.url.absoluteString)
            #expect(q.next(rules: RuleSet(), browsers: Fix.all) == nil) // picker still open
            q.pickerResolved()
        }
        #expect(seen == ["https://a.com", "https://b.com", "https://c.com"])
        #expect(q.next(rules: RuleSet(), browsers: Fix.all) == nil)
    }
    @Test func ruledLinkWaitsBehindOpenPicker() {
        let rules = RuleSet([DomainRule(domain: "b.com", bundleID: Fix.brave.id, browserName: "Brave")])
        var q = LinkQueue()
        q.enqueue(PendingLink(url: url("https://a.com")))
        q.enqueue(PendingLink(url: url("https://b.com")))
        _ = q.next(rules: rules, browsers: Fix.all)
        #expect(q.next(rules: rules, browsers: Fix.all) == nil)
        q.pickerResolved()
        #expect(q.next(rules: rules, browsers: Fix.all)?.decision == .open(Fix.brave))
    }
    @Test func ruleSavedForAAppliesToQueuedB() {
        var q = LinkQueue()
        q.enqueue(PendingLink(url: url("https://x.com/a")))
        q.enqueue(PendingLink(url: url("https://x.com/b")))
        _ = q.next(rules: RuleSet(), browsers: Fix.all)
        let saved = RuleSet([DomainRule(domain: "x.com", bundleID: Fix.firefox.id, browserName: "Firefox")])
        q.pickerResolved()
        #expect(q.next(rules: saved, browsers: Fix.all)?.decision == .open(Fix.firefox))
    }
    @Test func forcePickerJumpsAheadAndIgnoresRules() {
        let rules = RuleSet([DomainRule(domain: "a.com", bundleID: Fix.brave.id, browserName: "Brave")])
        var q = LinkQueue()
        q.enqueue(PendingLink(url: url("https://other.com")))
        q.pushFront(PendingLink(url: url("https://a.com"), forcePicker: true))
        let n = q.next(rules: rules, browsers: Fix.all)
        #expect(n?.link.url.host == "a.com")
        #expect(n?.decision == .showPicker(highlight: nil))
    }
}

struct PanelPlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let size = CGSize(width: 300, height: 200)

    @Test func centre() {
        let f = PanelPlacement.frame(size: size, cursor: CGPoint(x: 500, y: 400), screenVisibleFrame: screen)
        #expect(f.origin == CGPoint(x: 508, y: 192)) // top-left 8pt right/below the cursor
    }
    @Test func bottomRightFlipsLeftAndUp() {
        let f = PanelPlacement.frame(size: size, cursor: CGPoint(x: 990, y: 10), screenVisibleFrame: screen)
        #expect(f.origin == CGPoint(x: 682, y: 18))
        #expect(screen.contains(f))
    }
    @Test func topLeftStaysInside() {
        let f = PanelPlacement.frame(size: size, cursor: CGPoint(x: 0, y: 800), screenVisibleFrame: screen)
        #expect(screen.contains(f))
        #expect(f.origin.x == 8)
    }
    @Test func largerThanScreenPinsTopLeft() {
        let f = PanelPlacement.frame(size: CGSize(width: 1200, height: 900), cursor: CGPoint(x: 500, y: 400), screenVisibleFrame: screen)
        #expect(f.origin == CGPoint(x: 0, y: -100))
    }
    @Test func respectsNonZeroScreenOrigin() {
        let s = CGRect(x: 1000, y: -200, width: 1000, height: 800)
        let f = PanelPlacement.frame(size: size, cursor: CGPoint(x: 1995, y: -195), screenVisibleFrame: s)
        #expect(s.contains(f))
    }
}

@MainActor
struct PickerModelTests {
    func model(_ u: String = "https://github.com/x", highlight: Browser.ID? = nil, browsers: [Browser] = Fix.all) -> PickerModel {
        PickerModel(url: url(u), browsers: browsers, highlight: highlight)
    }
    @Test func numberKeyChooses() {
        #expect(model().handle(.digit(2)) == .choose(Fix.firefox, remember: false))
    }
    @Test func numberOutOfRangeIgnored() {
        #expect(model().handle(.digit(9)) == .none)
        #expect(model().handle(.digit(0)) == .none)
    }
    @Test func arrowsThenReturn() {
        let m = model()
        #expect(m.handle(.down) == .none)
        #expect(m.handle(.confirm) == .choose(Fix.firefox, remember: false))
    }
    @Test func arrowsClamp() {
        let m = model()
        _ = m.handle(.up)
        #expect(m.highlightIndex == 0)
        for _ in 0..<10 { _ = m.handle(.down) }
        #expect(m.highlightIndex == 2)
    }
    @Test func initialHighlightIsFirstOrOverride() {
        #expect(model().highlightIndex == 0)
        #expect(model(highlight: Fix.safari.id).highlightIndex == 2)
        #expect(model(highlight: "unknown").highlightIndex == 0)
    }
    @Test func rememberToggleAndChoose() {
        let m = model()
        #expect(!m.remember)
        _ = m.handle(.character("r"))
        #expect(m.remember)
        #expect(m.handle(.digit(1)) == .choose(Fix.brave, remember: true))
        _ = m.handle(.character("R"))
        #expect(!m.remember)
    }
    @Test func rememberIgnoredWithoutDomain() {
        let m = model("mailto:a@b.com")
        #expect(!m.canRemember)
        _ = m.handle(.character("r"))
        #expect(!m.remember)
        m.remember = true
        #expect(m.handle(.digit(1)) == .choose(Fix.brave, remember: false))
    }
    @Test func escapeCancels() {
        #expect(model().handle(.escape) == .cancel)
    }
    @Test func emptyListOnlyEscapeWorks() {
        let m = model(browsers: [])
        #expect(m.handle(.digit(1)) == .none)
        #expect(m.handle(.confirm) == .none)
        #expect(m.handle(.down) == .none)
        #expect(m.handle(.escape) == .cancel)
    }
    @Test func clickChooses() {
        let m = model()
        m.remember = true
        #expect(m.choose(index: 2) == .choose(Fix.safari, remember: true))
        #expect(m.choose(index: 7) == .none)
    }
}
