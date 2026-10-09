import Foundation

/// Normalizes a link's host into the key that domain rules are stored and matched by.
public enum DomainKey {
    /// Lowercased host with one leading `www.` removed (only when the remainder still has a dot).
    /// Returns `nil` for links without a host.
    public static func key(for url: URL) -> String? {
        guard var host = url.host(percentEncoded: false)?.lowercased() else { return nil }
        if host.hasPrefix("["), host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        guard !host.isEmpty else { return nil }
        if !isIPAddress(host), host.hasPrefix("www."), host.dropFirst(4).contains(".") {
            host = String(host.dropFirst(4))
        }
        return host
    }

    public static func isIPAddress(_ host: String) -> Bool {
        var v4 = in_addr()
        var v6 = in6_addr()
        return inet_pton(AF_INET, host, &v4) == 1 || inet_pton(AF_INET6, host, &v6) == 1
    }

    /// Dot-suffixes from longest to shortest: `a.b.c.com` → `a.b.c.com`, `b.c.com`, `c.com`, `com`.
    public static func suffixes(of domain: String) -> [String] {
        var result: [String] = []
        var rest = Substring(domain)
        while true {
            result.append(String(rest))
            guard let dot = rest.firstIndex(of: ".") else { break }
            rest = rest[rest.index(after: dot)...]
        }
        return result
    }
}
