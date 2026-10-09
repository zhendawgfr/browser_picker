import AppKit
import BrowserPickerCore

struct WorkspaceLocator: ApplicationLocating {
    func bundleIDs(forOpening url: URL) -> [String] {
        NSWorkspace.shared.urlsForApplications(toOpen: url).compactMap { Bundle(url: $0)?.bundleIdentifier }
    }

    func canonicalURL(forBundleID bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    func displayName(at appURL: URL) -> String {
        let name = FileManager.default.displayName(atPath: appURL.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
