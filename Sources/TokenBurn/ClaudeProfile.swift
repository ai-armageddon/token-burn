import Foundation

enum ClaudeProfile {
    private static func environment(for account: Account) throws -> [String: String] {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Token Burn/Claude Profiles", isDirectory: true)
            .appendingPathComponent(account.id.uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let config = directory.appendingPathComponent("usage-source.json")
        let source = Data(#"{"version":1,"providers":[{"id":"claude","enabled":true,"source":"cli","cookieSource":"off"}]}"#.utf8)
        if (try? Data(contentsOf: config)) != source { try source.write(to: config, options: .atomic) }
        return ["CLAUDE_CONFIG_DIR": directory.path, "CODEXBAR_CONFIG": config.path]
    }

    static func fetch(_ account: Account, signIn: Bool) throws -> Reading {
        guard let email = account.claudeProfileEmail else { throw FeedError.message("Choose a Claude account first.") }
        let env = try environment(for: account)
        if signIn {
            _ = try UsageFeed.execute(["auth", "login", "--claudeai", "--email", email], environment: env, executable: "claude")
        }
        let statusData = try UsageFeed.execute(["auth", "status", "--json"], environment: env, executable: "claude")
        let status = try JSONSerialization.jsonObject(with: statusData) as? [String: Any]
        guard status?["loggedIn"] as? Bool == true, let identity = status?["email"] as? String,
              identity.caseInsensitiveCompare(email) == .orderedSame else {
            throw FeedError.message("Sign in to Claude with \(email) to connect this account.")
        }
        let report = try UsageFeed.execute(["usage", "--provider", "claude", "--source", "cli", "--json"], environment: env)
        let rows = try UsageFeed.parse(report, provider: .claude)
        guard let reading = rows.compactMap(\.reading).first(where: { $0.identity?.caseInsensitiveCompare(email) == .orderedSame }) else {
            throw FeedError.message(rows.first?.issue ?? "Claude returned no verified allowance for \(email).")
        }
        return reading
    }
}
