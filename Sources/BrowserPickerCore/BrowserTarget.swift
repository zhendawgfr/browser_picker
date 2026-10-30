import Foundation

/// A browser profile. `id` is the stable identity (the profile's folder); `name` can be renamed.
public struct BrowserProfile: Hashable, Sendable {
    public let id: String
    public let name: String
    /// Appended to the label only when two names collide: the profile's folder name.
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

    /// Profile-less target for a browser that is listed by profile: opens the last-used profile, or Firefox's default one.
    public static func lastUsed(_ browser: Browser) -> BrowserTarget {
        let suffix = switch ProfileSource.forBundleID(browser.id) {
        case .firefox: "default profile"
        default: "last used profile"
        }
        return BrowserTarget(browser: browser, label: "\(browser.name) (\(suffix))")
    }
}

/// One profile of a Firefox profile group: a row of the group database's `Profiles` table.
public struct ProfileGroupEntry: Hashable, Sendable {
    /// Profile folder, relative to the Firefox root folder.
    public let path: String
    public let name: String

    public init(path: String, name: String) {
        self.path = path
        self.name = name
    }
}

/// Where a browser's profile list lives and how its profiles are opened.
public enum ProfileSource: Equatable, Sendable {
    /// Chromium user-data folder under Application Support; opened with `--profile-directory`.
    case chromium(String)
    /// Firefox root folder under Application Support; opened with `--profile <folder>`.
    case firefox(String)

    /// Browsers known to be targetable per profile.
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
        "org.mozilla.firefox": .firefox("Firefox"),
    ]

    public static func forBundleID(_ bundleID: String) -> ProfileSource? {
        table[bundleID]
    }

    /// State file relative to `~/Library/Application Support`.
    public var stateFile: String {
        switch self {
        case .chromium(let path): "\(path)/Local State"
        case .firefox(let root): "\(root)/profiles.ini"
        }
    }

    /// `group` returns a Firefox profile group's profiles by store ID; Chromium ignores it.
    public func parse(_ data: Data, group: (String) -> [ProfileGroupEntry]? = { _ in nil }) -> [BrowserProfile]? {
        switch self {
        case .chromium: ChromiumProfiles.parse(data)
        case .firefox: FirefoxProfiles.parse(data, group: group)
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

public enum FirefoxProfiles {
    /// Profiles listed in Firefox's `profiles.ini`, with each profile group replaced by the group's own profiles.
    /// `id` is the profile folder as Firefox stores it. `nil` when the data is not UTF-8 or lists no profile.
    public static func parse(_ data: Data, group: (String) -> [ProfileGroupEntry]?) -> [BrowserProfile]? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var result: [BrowserProfile] = []
        var seen = Set<String>()
        func add(path: String, name: String) {
            guard !path.isEmpty, !name.isEmpty, seen.insert(path).inserted else { return }
            result.append(BrowserProfile(id: path, name: name, disambiguator: (path as NSString).lastPathComponent))
        }
        for (section, values) in sections(text) where section.hasPrefix("Profile") && section.count > 7
            && section.dropFirst(7).allSatisfy(\.isNumber) {
            guard let path = values["Path"], !path.isEmpty else { continue }
            // A group's section follows its most recently used profile; list the group's profiles instead.
            if let storeID = values["StoreID"], !storeID.isEmpty, let rows = group(storeID), !rows.isEmpty {
                for row in rows { add(path: row.path, name: row.name) }
            } else {
                add(path: path, name: values["Name"] ?? "")
            }
        }
        return result.isEmpty ? nil : result
    }

    /// INI sections in file order, each with its `key=value` pairs. `;` and `#` start comment lines.
    static func sections(_ text: String) -> [(name: String, values: [String: String])] {
        var result: [(name: String, values: [String: String])] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                result.append((String(line.dropFirst().dropLast()), [:]))
            } else if let equals = line.firstIndex(of: "="), !result.isEmpty {
                let key = line[..<equals].trimmingCharacters(in: .whitespaces)
                result[result.count - 1].values[key] = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            }
        }
        return result
    }
}
