import Foundation
import Security

/// Fetches Claude 5h / 7d usage from the same OAuth usage endpoint the Claude Code
/// status line uses. Claude Code does not persist rate limits to any readable file
/// (unlike Codex rollout logs), so the only source is `GET /api/oauth/usage`
/// authenticated with the OAuth token Claude Code stores in the login keychain.
///
/// Throttling matches the status-line tooling: at most one request per
/// `minRefreshInterval` seconds, gated by the caller against the cached snapshot's
/// age, so the endpoint is hit roughly once every 3 minutes during active use and
/// never while idle.
enum ClaudeUsageAPIClient {
    /// Minimum seconds between live fetches (ccstatusline's CACHE_MAX_AGE = 180s).
    static let minRefreshInterval: TimeInterval = 180

    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")
    private static let keychainService = "Claude Code-credentials"
    private static let oauthBetaHeader = "oauth-2025-04-20"
    private static let requestTimeout: TimeInterval = 5

    /// Returns the current snapshot, or nil on any failure (no token, expired token,
    /// non-200, parse error) so the caller keeps using its disk cache.
    nonisolated static func fetch() async -> ClaudeUsageSnapshot? {
        guard let usageURL, let token = accessToken() else { return nil }

        var request = URLRequest(url: usageURL, timeoutInterval: requestTimeout)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(oauthBetaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("PingIsland", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }

        return ClaudeUsageLoader.snapshot(fromPayload: payload, cachedAt: Date())
    }

    /// Reads Claude Code's OAuth access token from the login keychain item
    /// `Claude Code-credentials` (JSON blob: `{ "claudeAiOauth": { "accessToken": … } }`).
    private nonisolated static func accessToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let blob = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = blob["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else {
            return nil
        }

        return token
    }
}
