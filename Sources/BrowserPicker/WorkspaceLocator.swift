import AppKit
import BrowserPickerCore

struct WorkspaceLocator: ApplicationLocating {
    func bundleIDs(forOpening url: URL) -> [String] {
        NSWorkspace.shared.urlsForApplications(toOpen: url).compactMap { Bundle(url: $0)?.bundleIdentifier }
    }

    func canonicalURL(forBundleID bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    func profileState(forBundleID bundleID: String) -> Data? {
        guard let source = ProfileSource.forBundleID(bundleID),
              let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        // Fails with EPERM unless Browser Picker has Full Disk Access; callers then fall back to one entry.
        return try? Data(contentsOf: support.appending(path: source.stateFile))
    }

    func profileStateDate(forBundleID bundleID: String) -> Date? {
        guard let source = ProfileSource.forBundleID(bundleID),
              let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let path = support.appending(path: source.stateFile).path
        return (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    func isProfileStateBlocked(forBundleID bundleID: String) -> Bool {
        guard let source = ProfileSource.forBundleID(bundleID),
              let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return false }
        do {
            try FileHandle(forReadingFrom: support.appending(path: source.stateFile)).close()
            return false
        } catch let error as NSError {
            let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
            return error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError
                || underlying?.domain == NSPOSIXErrorDomain && underlying?.code == Int(EPERM)
        }
    }

    func displayName(at appURL: URL) -> String {
        let name = FileManager.default.displayName(atPath: appURL.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
