import Foundation

struct BankedResets: Codable, Equatable {
    struct Grant: Codable, Equatable {
        var title: String
        var expiry: Date?
        var detail: String {
            title + " · " + (expiry.map { "Expires " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "Expiry unavailable")
        }
    }
    var grants: [Grant] = []
    // Some providers publish only a total and the earliest expiry.
    var reportedCount: Int?
    var nextExpiry: Date?
    var expiryNote: String?

    var dates: [Date] { grants.compactMap(\.expiry) + [nextExpiry].compactMap { $0 } }

    func available(at now: Date) -> (count: Int, lines: [String]) {
        if let reportedCount {
            if let nextExpiry, nextExpiry <= now { return (0, []) }
            let next = nextExpiry.map { "Next expiry · " + $0.formatted(date: .abbreviated, time: .shortened) }
            return (reportedCount, [next ?? expiryNote ?? "Expiry unavailable"])
        }
        let active = grants.filter { ($0.expiry ?? .distantFuture) > now }
            .sorted { ($0.expiry ?? .distantFuture) < ($1.expiry ?? .distantFuture) }
        return (active.count, active.map(\.detail))
    }

    static func parse(usage: [String: Any], entry: [String: Any], provider: Provider) -> Self? {
        typealias Fields = [String: Any]
        if provider == .codex {
            if let inventory = usage["codexResetCredits"] as? Fields, let list = inventory["credits"] as? [Fields] {
                let grants = list.compactMap { item -> Grant? in
                    guard item["status"] as? String == "available" else { return nil }
                    let expiry = UsageFeed.date(item["expires_at"])
                    if item["expires_at"] is String && expiry == nil { return nil }
                    return Grant(title: item["title"] as? String ?? "Full reset", expiry: expiry)
                }
                return Self(grants: grants)
            }
            if let summary = entry["resetCredits"] as? Fields,
               let count = summary["available"] as? Int, count > 0 {
                return Self(reportedCount: count, nextExpiry: UsageFeed.date(summary["nextExpiresAt"]))
            }
        }
        if provider == .claude {
            for section in usage["details"] as? [Fields] ?? [] {
                for row in section["rows"] as? [Fields] ?? [] where row["label"] as? String == "Limit Reset Credits" {
                    guard let value = row["value"] as? String, let word = value.split(separator: " ").first,
                          let count = Int(word), (1...50).contains(count) else { continue }
                    return Self(reportedCount: count, expiryNote: row["secondaryValue"] as? String)
                }
            }
        }
        return nil
    }
}

extension Account {
    var claudeResetNote: String? {
        guard provider == .claude, !manual, let reading, reading.bankedResets == nil else { return nil }
        switch reading.source.lowercased() {
        case "claude", "cli": return "Banked resets unavailable from the Claude CLI."
        default: return "Claude did not report a banked-reset count in this reading."
        }
    }
}
