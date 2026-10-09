import Foundation
@testable import BrowserPickerCore

func url(_ s: String) -> URL { URL(string: s)! }

enum Fix {
    static let brave = Browser(id: "com.brave.Browser", name: "Brave Browser", appURL: url("file:///Applications/Brave%20Browser.app"))
    static let safari = Browser(id: "com.apple.Safari", name: "Safari", appURL: url("file:///Applications/Safari.app"))
    static let firefox = Browser(id: "org.mozilla.firefox", name: "Firefox", appURL: url("file:///Applications/Firefox.app"))
    static let all = [brave, firefox, safari]

    @MainActor static func freshDefaults() -> UserDefaults {
        let name = "test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }
}
