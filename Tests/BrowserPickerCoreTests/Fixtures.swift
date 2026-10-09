import Foundation
@testable import BrowserPickerCore

func url(_ s: String) -> URL { URL(string: s)! }

enum Fix {
    static let brave = Browser(id: "com.brave.Browser", name: "Brave Browser", appURL: url("file:///Applications/Brave%20Browser.app"))
    static let safari = Browser(id: "com.apple.Safari", name: "Safari", appURL: url("file:///Applications/Safari.app"))
    static let firefox = Browser(id: "org.mozilla.firefox", name: "Firefox", appURL: url("file:///Applications/Firefox.app"))
    static let all = [brave, firefox, safari]

    static let tBrave = BrowserTarget(browser: brave)
    static let tSafari = BrowserTarget(browser: safari)
    static let tFirefox = BrowserTarget(browser: firefox)
    static let allTargets = [tBrave, tFirefox, tSafari]

    static let personal = BrowserProfile(id: "Default", name: "Personal")
    static let work = BrowserProfile(id: "Profile 1", name: "Work")
    static let tPersonal = BrowserTarget(browser: brave, profile: personal, label: "Brave Browser — Personal")
    static let tWork = BrowserTarget(browser: brave, profile: work, label: "Brave Browser — Work")
    static let profileTargets = [tPersonal, tWork, tSafari]

    @MainActor static func freshDefaults() -> UserDefaults {
        let name = "test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }
}
