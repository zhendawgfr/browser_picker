import Foundation

/// A Chromium profile or an Arc Space. `id` is the stable identity (folder name or Space ID); `name` can be renamed.
public struct BrowserProfile: Hashable, Sendable {
    public let id: String
    public let name: String
    /// Appended to the label only when two names collide: the folder name, or "Space <n>" for Arc.
    public let disambiguator: String

    public init(id: String, name: String, disambiguator: String? = nil) {
        self.id = id
        self.name = name
        self.disambiguator = disambiguator ?? id
    }
}

public struct TargetID: Hashable, Sendable {
    public let bundleID: String
    public let profileID: String?

    public init(bundleID: String, profileID: String? = nil) {
        self.bundleID = bundleID
        self.profileID = profileID
    }
}

/// One choice in the picker: a browser, or one profile of a browser.
public struct BrowserTarget: Identifiable, Hashable, Sendable {
    public let browser: Browser
    public let profile: BrowserProfile?
    public let label: String

    public var id: TargetID { TargetID(bundleID: browser.id, profileID: profile?.id) }

    public init(browser: Browser, profile: BrowserProfile? = nil, label: String? = nil) {
        self.browser = browser
        self.profile = profile
        self.label = label ?? browser.name
    }

    /// Profile-less target for a browser that is listed by profile: opens the last-used profile, or Arc's current Space.
    public static func lastUsed(_ browser: Browser) -> BrowserTarget {
        let suffix = ProfileSource.forBundleID(browser.id) == .arcSpaces ? "current Space" : "last used profile"
        return BrowserTarget(browser: browser, label: "\(browser.name) (\(suffix))")
    }
}

/// Where a browser's profile list lives and how its profiles are opened.
public enum ProfileSource: Equatable, Sendable {
    /// Chromium user-data folder under Application Support; opened with `--profile-directory`.
    case chromium(String)
    /// Arc Spaces from the sidebar file; opened through AppleScript.
    case arcSpaces

    public static let arcBundleID = "company.thebrowser.Browser"

    /// Browsers known to be targetable per profile or Space.
    private static let table: [String: ProfileSource] = [
        "com.brave.Browser": .chromium("BraveSoftware/Brave-Browser"),
        "com.brave.Browser.beta": .chromium("BraveSoftware/Brave-Browser-Beta"),
        "com.brave.Browser.nightly": .chromium("BraveSoftware/Brave-Browser-Nightly"),
        "com.google.Chrome": .chromium("Google/Chrome"),
        "com.google.Chrome.beta": .chromium("Google/Chrome Beta"),
        "com.google.Chrome.canary": .chromium("Google/Chrome Canary"),
        "com.microsoft.edgemac": .chromium("Microsoft Edge"),
        "com.microsoft.edgemac.Beta": .chromium("Microsoft Edge Beta"),
        "com.microsoft.edgemac.Dev": .chromium("Microsoft Edge Dev"),
        "com.vivaldi.Vivaldi": .chromium("Vivaldi"),
        "org.chromium.Chromium": .chromium("Chromium"),
        arcBundleID: .arcSpaces,
    ]

    public static func forBundleID(_ bundleID: String) -> ProfileSource? {
        table[bundleID]
    }

    /// State file relative to `~/Library/Application Support`.
    public var stateFile: String {
        switch self {
        case .chromium(let path): "\(path)/Local State"
        case .arcSpaces: "Arc/StorableSidebar.json"
        }
    }

    public func parse(_ data: Data) -> [BrowserProfile]? {
        switch self {
        case .chromium: ChromiumProfiles.parse(data)
        case .arcSpaces: ArcSpaces.parse(data)
        }
    }
}

public enum ChromiumProfiles {
    /// Profiles listed in a `Local State` file, sorted by folder name. `nil` when the data is malformed or lists none.
    public static func parse(_ data: Data) -> [BrowserProfile]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: Any] else { return nil }
        var result: [BrowserProfile] = []
        for (directory, value) in cache {
            guard let info = value as? [String: Any],
                  info["is_omitted_from_profile_list"] as? Bool != true,
                  let name = info["name"] as? String, !name.isEmpty else { continue }
            result.append(BrowserProfile(id: directory, name: name))
        }
        return result.isEmpty ? nil : result.sorted { $0.id < $1.id }
    }
}

public enum ArcSpaces {
    /// Titled Spaces from Arc's `StorableSidebar.json`, in sidebar order. `nil` when the data is malformed or has none.
    public static func parse(_ data: Data) -> [BrowserProfile]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sidebar = root["sidebar"] as? [String: Any],
              let containers = sidebar["containers"] as? [Any] else { return nil }
        var result: [BrowserProfile] = []
        var seen = Set<String>()
        for case let container as [String: Any] in containers {
            // `spaces` alternates an ID string and the Space object.
            for case let space as [String: Any] in container["spaces"] as? [Any] ?? [] {
                guard let id = space["id"] as? String, let title = space["title"] as? String,
                      !title.isEmpty, seen.insert(id).inserted else { continue }
                result.append(BrowserProfile(id: id, name: title, disambiguator: "Space \(result.count + 1)"))
            }
        }
        return result.isEmpty ? nil : result
    }
}
