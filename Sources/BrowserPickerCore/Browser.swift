import Foundation

public struct Browser: Identifiable, Hashable, Sendable {
    /// Bundle identifier.
    public let id: String
    public let name: String
    public let appURL: URL

    public init(id: String, name: String, appURL: URL) {
        self.id = id
        self.name = name
        self.appURL = appURL
    }
}

/// Abstraction over LaunchServices so discovery can be tested with fakes.
public protocol ApplicationLocating: Sendable {
    /// Bundle identifiers of apps that can open `url`. May contain several copies of one app.
    func bundleIDs(forOpening url: URL) -> [String]
    /// The copy of the app that macOS resolves for `bundleID`.
    func canonicalURL(forBundleID bundleID: String) -> URL?
    func displayName(at appURL: URL) -> String
    /// Contents of the browser's profile state file, or `nil` when it has none or it cannot be read.
    func profileState(forBundleID bundleID: String) -> Data?
    /// Modification date of that file, used to skip re-parsing an unchanged file. `nil` when unknown.
    func profileStateDate(forBundleID bundleID: String) -> Date?
    /// True when the file exists but macOS refuses to open it (Chrome and Brave without Full Disk Access).
    func isProfileStateBlocked(forBundleID bundleID: String) -> Bool
}

extension ApplicationLocating {
    public func profileStateDate(forBundleID bundleID: String) -> Date? { nil }
    public func isProfileStateBlocked(forBundleID bundleID: String) -> Bool { false }
}

/// Parsed profile lists keyed by bundle ID and file modification date. Arc's sidebar file is several MB.
final class ProfileCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: (date: Date, profiles: [BrowserProfile])] = [:]

    func profiles(for bundleID: String, date: Date?, load: () -> [BrowserProfile]?) -> [BrowserProfile]? {
        guard let date else { return load() }
        if let hit = lock.withLock({ entries[bundleID] }), hit.date == date { return hit.profiles }
        let profiles = load()
        // A failed read is not cached: after a Full Disk Access grant the unchanged file must be read again.
        if let profiles { lock.withLock { entries[bundleID] = (date, profiles) } }
        return profiles
    }
}

public struct BrowserCatalog: Sendable {
    private let locator: any ApplicationLocating
    private let ownBundleID: String?
    private let cache = ProfileCache()

    public init(locator: any ApplicationLocating, ownBundleID: String?) {
        self.locator = locator
        self.ownBundleID = ownBundleID
    }

    public func browsers() -> [Browser] {
        let probe = URL(string: "https://example.com")!
        var seen = Set<String>()
        var result: [Browser] = []
        for bundleID in locator.bundleIDs(forOpening: probe) {
            guard bundleID != ownBundleID, seen.insert(bundleID).inserted,
                  let url = locator.canonicalURL(forBundleID: bundleID) else { continue }
            result.append(Browser(id: bundleID, name: locator.displayName(at: url), appURL: url))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Installed profile-capable browsers whose profile list macOS blocks, for the Settings hint.
    public func blockedBrowsers() -> [Browser] {
        browsers().filter { ProfileSource.forBundleID($0.id) != nil && locator.isProfileStateBlocked(forBundleID: $0.id) }
    }

    /// Parses changed profile files into the cache off the main thread, so the next picker is fast.
    public func warmUp(after delay: Duration = .zero) {
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: delay)
            _ = targets()
        }
    }

    /// Browsers expanded into one target per profile where the browser lists several (see browser-profiles spec).
    public func targets() -> [BrowserTarget] {
        browsers().flatMap { browser -> [BrowserTarget] in
            guard let source = ProfileSource.forBundleID(browser.id),
                  let profiles = cache.profiles(for: browser.id, date: locator.profileStateDate(forBundleID: browser.id), load: {
                      locator.profileState(forBundleID: browser.id).flatMap(source.parse)
                  }) else {
                return [BrowserTarget(browser: browser)]
            }
            if profiles.count == 1 {
                // A lone Chromium profile is still targeted, so a rule saved from it survives adding a second one.
                // A lone Arc Space is not, so Arc with one Space never needs the Automation permission.
                return [BrowserTarget(browser: browser, profile: source == .arcSpaces ? nil : profiles[0])]
            }
            let nameCounts = Dictionary(profiles.map { ($0.name, 1) }, uniquingKeysWith: +)
            return profiles
                .sorted {
                    let order = $0.name.localizedCaseInsensitiveCompare($1.name)
                    return order == .orderedSame ? $0.disambiguator.localizedStandardCompare($1.disambiguator) == .orderedAscending : order == .orderedAscending
                }
                .map { profile in
                    var label = "\(browser.name) — \(profile.name)"
                    if nameCounts[profile.name, default: 0] > 1 { label += " (\(profile.disambiguator))" }
                    return BrowserTarget(browser: browser, profile: profile, label: label)
                }
        }
    }
}
