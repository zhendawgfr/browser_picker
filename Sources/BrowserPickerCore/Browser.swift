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
}

public struct BrowserCatalog: Sendable {
    private let locator: any ApplicationLocating
    private let ownBundleID: String?

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
}
