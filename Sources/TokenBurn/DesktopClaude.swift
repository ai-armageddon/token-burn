import Foundation

enum DesktopClaude {
    // These files identify the current accounts. CodexBar manages authentication.
    static func accountKey() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        func metadata(_ path: String) -> [String: Any]? {
            guard let data = try? Data(contentsOf: home.appendingPathComponent(path)) else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        guard let raw = metadata("Library/Application Support/Claude/config.json")?["lastKnownAccountUuid"] as? String,
              let id = UUID(uuidString: raw) else { return nil }
        let cli = metadata(".claude.json")?["oauthAccount"] as? [String: Any]
        if let other = cli?["accountUuid"] as? String, UUID(uuidString: other) == id { return nil }
        return "claude-desktop:" + id.uuidString.lowercased()
    }

    static func configuration() throws -> URL {
        // Scope desktop reads to an independent config, preserving the regular browser/CLI account.
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Token Burn", isDirectory: true)
        let file = folder.appendingPathComponent("claude-desktop-source.json")
        let data = Data(#"{"version":1,"providers":[{"id":"claude","enabled":true,"source":"web","cookieSource":"auto","claudeDesktopCookiesEnabled":true}]}"#.utf8)
        if (try? Data(contentsOf: file)) != data { try data.write(to: file, options: .atomic) }
        return file
    }

    static func connect() -> String {
        do {
            let config = try configuration()
            let data = try UsageFeed.execute(["cookie", "refresh", "--provider", "claude", "--allow-keychain-prompt", "--json"],
                                             environment: ["CODEXBAR_CONFIG": config.path])
            let result = try JSONSerialization.jsonObject(with: data)
            if let rows = result as? [[String: Any]], rows.first?["status"] as? String == "failed" {
                return rows.first?["message"] as? String ?? "Check the Claude Desktop login and macOS Keychain access."
            }
            return "Checking the Claude Desktop reading…"
        } catch { return error.localizedDescription }
    }
}
