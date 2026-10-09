import AppKit
import Observation

@MainActor
@Observable
final class DefaultBrowserService {
    private(set) var isDefault = false
    private(set) var lastError: String?

    init() { refresh() }

    func refresh() {
        let probe = URL(string: "https://example.com")!
        guard let handler = NSWorkspace.shared.urlForApplication(toOpen: probe),
              let own = Bundle.main.bundleIdentifier else {
            isDefault = false
            return
        }
        isDefault = Bundle(url: handler)?.bundleIdentifier == own
    }

    /// Sets `http`, then `https`; skips `https` if the `http` prompt is declined.
    func makeDefault() async {
        lastError = nil
        let appURL = Bundle.main.bundleURL
        do {
            try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "http")
            try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "https")
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }
}
