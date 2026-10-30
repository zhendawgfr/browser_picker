import AppKit
import BrowserPickerCore
import SQLite3

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
        var files = [support.appending(path: source.stateFile)]
        if case .firefox(let root) = source {
            // Renaming a profile in Firefox's profile manager may only touch a group database or its WAL.
            let groups = support.appending(path: "\(root)/Profile Groups")
            let names = (try? FileManager.default.contentsOfDirectory(atPath: groups.path)) ?? []
            files += names.filter { $0.hasSuffix(".sqlite") || $0.hasSuffix(".sqlite-wal") }.map { groups.appending(path: $0) }
        }
        return files.compactMap { (try? FileManager.default.attributesOfItem(atPath: $0.path))?[.modificationDate] as? Date }.max()
    }

    /// Reads a Firefox profile group's `Profiles` table, read-only, so Firefox's data is never written.
    func profileGroup(forBundleID bundleID: String, storeID: String) -> [ProfileGroupEntry]? {
        guard case .firefox(let root)? = ProfileSource.forBundleID(bundleID),
              // The store ID comes from profiles.ini and becomes a file name: keep it from naming another file.
              !storeID.isEmpty, storeID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let file = support.appending(path: "\(root)/Profile Groups/\(storeID).sqlite")
        // Firefox keeps the database in WAL mode and deletes its -shm file on quit, and a read-only connection
        // cannot recreate it. A cleanly closed database is fully checkpointed, so read it as immutable then.
        return Self.profileRows(at: file.path, flags: SQLITE_OPEN_READONLY)
            ?? Self.profileRows(at: file.absoluteString + "?immutable=1", flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_URI)
    }

    private static func profileRows(at location: String, flags: Int32) -> [ProfileGroupEntry]? {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(location, &db, flags, nil) == SQLITE_OK else { return nil }
        sqlite3_busy_timeout(db, 100)
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT path, name FROM Profiles ORDER BY id", -1, &statement, nil) == SQLITE_OK else { return nil }
        var rows: [ProfileGroupEntry] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let path = sqlite3_column_text(statement, 0), let name = sqlite3_column_text(statement, 1) else { continue }
                rows.append(ProfileGroupEntry(path: String(cString: path), name: String(cString: name)))
            case SQLITE_DONE:
                return rows
            default:
                return nil
            }
        }
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
