import Foundation

/// The release check from src/main/updates.js: ask GitHub for the latest release, and say so only
/// when its tag is newer than the running version. Every failure is silent, as in v2.
public enum UpdateCheck {
    public static let releasesAPI = URL(string: "https://api.github.com/repos/jkotzker/fromscratch/releases/latest")!
    /// RELEASES_URL in App.jsx, opened when the bar is clicked.
    public static let releasesPage = URL(string: "https://github.com/jkotzker/fromscratch/releases")!
    public static let timeout: TimeInterval = 10

    /// `latestTag` without its leading `v` when it is newer than `current`, otherwise nil.
    /// Compares numerically, component by component (3.10.0 is newer than 3.9.0). Where v2's
    /// compare-versions library orders pre-releases, this answers nil for anything that is not
    /// plain dot-separated numbers on both sides: a beta tag never prompts a stable user.
    public static func newerVersion(latestTag: String, current: String) -> String? {
        let latest = stripV(latestTag)
        guard let latestParts = numericComponents(latest),
              let currentParts = numericComponents(stripV(current)) else { return nil }
        let count = max(latestParts.count, currentParts.count)
        for index in 0..<count {
            let l = index < latestParts.count ? latestParts[index] : 0
            let c = index < currentParts.count ? currentParts[index] : 0
            if l != c { return l > c ? latest : nil }
        }
        return nil
    }

    /// The `tag_name` of the latest release, or nil on any failure (no release yet, rate limit,
    /// no network, a malformed body).
    public static func fetchLatestTag(session: URLSession) async -> String? {
        var request = URLRequest(url: releasesAPI, timeoutInterval: timeout)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = object["tag_name"] as? String, !tag.isEmpty else { return nil }
            return tag
        } catch {
            return nil
        }
    }

    private static func stripV(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
    }

    /// nil unless every dot-separated component is a non-empty run of ASCII digits.
    private static func numericComponents(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0 >= "0" && $0 <= "9" }), let n = Int(part) else { return nil }
            numbers.append(n)
        }
        return numbers
    }
}
