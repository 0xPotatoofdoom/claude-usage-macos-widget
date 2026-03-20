import Foundation

// MARK: - Plan Usage Data (from claude.ai subscription)

struct PlanUsage: Codable, Sendable {
    var sessionPercent: Double = 0        // five_hour utilization
    var sessionResetsAt: Date?
    var weeklyAllPercent: Double = 0      // seven_day utilization
    var weeklyAllResetsAt: Date?
    var weeklySonnetPercent: Double = 0   // seven_day_sonnet utilization
    var weeklySonnetResetsAt: Date?
    var weeklyOpusPercent: Double = 0     // seven_day_opus utilization
    var weeklyOpusResetsAt: Date?
    var fetchedAt: Date = .distantPast

    var sessionResetFormatted: String { formatReset(sessionResetsAt) }
    var weeklyAllResetFormatted: String { formatReset(weeklyAllResetsAt) }
    var weeklySonnetResetFormatted: String { formatReset(weeklySonnetResetsAt) }

    var fetchedAgo: String {
        if fetchedAt == .distantPast { return "never" }
        let seconds = Int(Date().timeIntervalSince(fetchedAt))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }

    private func formatReset(_ date: Date?) -> String {
        guard let date else { return "" }
        let remaining = date.timeIntervalSince(Date())
        if remaining <= 0 { return "now" }

        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60

        if hours >= 24 {
            let days = hours / 24
            let h = hours % 24
            return "\(days)d \(h)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Shared Data Store

struct SharedDataStore: Sendable {
    static let appGroupID = "YOUR_TEAM_ID.com.claudethrottle.shared"
    static let planUsageKey = "planUsage"

    static func savePlanUsage(_ usage: PlanUsage) {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = try? JSONEncoder().encode(usage) else { return }
        defaults.set(data, forKey: planUsageKey)
    }

    static func loadPlanUsage() -> PlanUsage? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: planUsageKey),
              let usage = try? JSONDecoder().decode(PlanUsage.self, from: data) else {
            return nil
        }
        return usage
    }
}

// MARK: - OAuth Usage Fetcher

actor ClaudeUsageFetcher {
    func fetchUsage() async throws -> PlanUsage {
        // Get OAuth token from Keychain
        guard let token = Self.getOAuthToken() else {
            throw UsageFetchError.noToken
        }

        let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UsageFetchError.badResponse
        }

        if httpResponse.statusCode == 429 {
            throw UsageFetchError.rateLimited
        }

        guard httpResponse.statusCode == 200 else {
            throw UsageFetchError.httpError(httpResponse.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageFetchError.parseError
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var usage = PlanUsage()
        usage.fetchedAt = Date()

        if let fiveHour = json["five_hour"] as? [String: Any] {
            usage.sessionPercent = fiveHour["utilization"] as? Double ?? 0
            if let resetStr = fiveHour["resets_at"] as? String {
                usage.sessionResetsAt = iso.date(from: resetStr)
            }
        }

        if let sevenDay = json["seven_day"] as? [String: Any] {
            usage.weeklyAllPercent = sevenDay["utilization"] as? Double ?? 0
            if let resetStr = sevenDay["resets_at"] as? String {
                usage.weeklyAllResetsAt = iso.date(from: resetStr)
            }
        }

        if let sonnet = json["seven_day_sonnet"] as? [String: Any] {
            usage.weeklySonnetPercent = sonnet["utilization"] as? Double ?? 0
            if let resetStr = sonnet["resets_at"] as? String {
                usage.weeklySonnetResetsAt = iso.date(from: resetStr)
            }
        }

        if let opus = json["seven_day_opus"] as? [String: Any] {
            usage.weeklyOpusPercent = opus["utilization"] as? Double ?? 0
            if let resetStr = opus["resets_at"] as? String {
                usage.weeklyOpusResetsAt = iso.date(from: resetStr)
            }
        }

        return usage
    }

    private static func getOAuthToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else {
            return nil
        }
        return token
    }
}

enum UsageFetchError: Error, LocalizedError {
    case noToken
    case badResponse
    case rateLimited
    case httpError(Int)
    case parseError

    var errorDescription: String? {
        switch self {
        case .noToken: return "No Claude Code OAuth token found"
        case .badResponse: return "Bad response from server"
        case .rateLimited: return "Rate limited, try again later"
        case .httpError(let code): return "HTTP error \(code)"
        case .parseError: return "Failed to parse response"
        }
    }
}
