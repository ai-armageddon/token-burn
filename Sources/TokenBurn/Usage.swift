import Foundation

enum Provider: String, Codable, CaseIterable, Identifiable {
    case claude, codex, opencodego, grok
    var id: Self { self }
    var name: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .opencodego: return "OpenCode"
        case .grok: return "Grok"
        }
    }
    var dashboard: URL {
        let address: String
        switch self {
        case .claude: address = "https://claude.ai/settings/usage"
        case .codex: address = "https://chatgpt.com/codex/settings/usage"
        case .opencodego: address = "https://opencode.ai/console"
        case .grok: address = "https://grok.com/dashboard"
        }
        return URL(string: address)!
    }
}

struct Meter: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var percent: Double
    var reset: Date?
    var remaining: Double { min(100, max(0, 100 - percent)) }
    var isLow: Bool { remaining < 20 }
    var remainingText: String {
        if remaining > 0 && remaining < 1 { return "<1%" }
        return "\(Int(remaining.rounded()))%"
    }
}

struct Reading: Codable, Equatable {
    var meters: [Meter]
    var updated: Date
    var identity: String?
    var plan: String?
    var source: String
    var estimated: Bool
    var bankedResets: BankedResets?
}

struct Account: Identifiable, Codable {
    var id = UUID()
    var provider: Provider
    var key: String?
    var label = ""
    var manual = false
    var hidden = false
    var preferred = ""
    var reading: Reading?
    var issue: String?
    var customTier: String?
    var customPrice: String?
    var meter: Meter? {
        reading?.meters.first { $0.id == preferred } ?? reading?.meters.first
    }
    // Keep the selected window outside and show one other standard allowance inside.
    var innerMeter: Meter? {
        reading?.meters.first { $0.id != meter?.id && ["primary", "secondary", "tertiary"].contains($0.id) }
    }
    var isDesktopClaude: Bool { provider == .claude && key?.hasPrefix("claude-desktop:") == true }
    var name: String { label.isEmpty ? provider.name : label }
    var accountLabel: String? { isDesktopClaude ? (reading?.identity ?? "Claude Desktop") : key }
    var stale: Bool {
        guard let reading else { return false }
        if let reset = meter?.reset, reset <= Date() { return true }
        return !manual && (issue != nil || Date().timeIntervalSince(reading.updated) > 660)
    }
}

struct Observation {
    var key: String?
    var reading: Reading?
    var issue: String?
}

enum FeedError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}

enum UsageFeed {
    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let format = ISO8601DateFormatter()
        if let value = format.date(from: text) { return value }
        format.formatOptions.insert(.withFractionalSeconds)
        return format.date(from: text)
    }

    static func parse(_ data: Data, provider: Provider) throws -> [Observation] {
        typealias Fields = [String: Any]
        guard let entries = try JSONSerialization.jsonObject(with: data) as? [Fields] else {
            throw FeedError.message("CodexBar returned an unreadable usage report.")
        }
        let observations: [Observation] = entries.filter { $0["provider"] as? String == provider.rawValue }.map { entry in
            let usage = entry["usage"] as? Fields ?? [:]
            let identity = usage["identity"] as? Fields ?? [:]
            let email = usage["accountEmail"] as? String ?? identity["accountEmail"] as? String
            let key = entry["account"] as? String ?? email
            let labels = entry["rateWindowLabels"] as? [String: String] ?? [:]
            func meter(_ raw: Any?, id: String, title: String?) -> Meter? {
                guard let raw = raw as? Fields, let number = raw["usedPercent"] as? Double,
                      number.isFinite, number >= 0, number <= 100 else { return nil }
                let fallback: String
                switch raw["windowMinutes"] as? Int {
                case 300: fallback = "5-hour window"
                case 10080: fallback = "Weekly"
                case 43200: fallback = "Monthly"
                default: fallback = "Usage window"
                }
                return Meter(id: id, title: title ?? fallback, percent: number, reset: date(raw["resetsAt"]))
            }
            var meters = ["primary", "secondary", "tertiary"].compactMap {
                meter(usage[$0], id: $0, title: labels[$0])
            }
            for item in usage["extraRateWindows"] as? [Fields] ?? [] {
                if let id = item["id"] as? String, let extra = meter(item["window"], id: id, title: item["title"] as? String) {
                    meters.append(extra)
                }
            }
            if let message = (entry["error"] as? Fields)?["message"] as? String {
                return Observation(key: key, issue: message)
            }
            let bank = BankedResets.parse(usage: usage, entry: entry, provider: provider)
            guard !meters.isEmpty || (bank?.available(at: Date()).count ?? 0) > 0 else { return Observation(key: key, issue: "No usage window was reported for this account.") }
            let source = entry["source"] as? String ?? "provider"
            let plan = (usage["planObservation"] as? Fields)?["rawPlan"] as? String
                ?? usage["loginMethod"] as? String ?? identity["loginMethod"] as? String
            let reading = Reading(meters: meters, updated: date(usage["updatedAt"]) ?? Date(), identity: email ?? key,
                                  plan: plan, source: source,
                                  estimated: usage["dataConfidence"] as? String == "estimated" || (provider == .opencodego && source == "local"),
                                  bankedResets: bank)
            return Observation(key: key, reading: reading)
        }
        guard !observations.isEmpty else { throw FeedError.message("CodexBar returned no accounts.") }
        return observations
    }

    static func fetch(_ provider: Provider, desktopKeys: Set<String>) -> [Observation] {
        do {
            var accounts = try query(provider, all: true)
            if accounts.count == 1, accounts[0].key == nil, accounts[0].issue?.localizedCaseInsensitiveContains("no token accounts configured") == true {
                accounts = try query(provider, all: false)
            }
            if provider == .claude, let desktop = DesktopClaude.accountKey() {
                guard desktopKeys.contains(desktop) else {
                    accounts.append(Observation(key: desktop))
                    return accounts
                }
                let result: Observation
                do {
                    let config = try DesktopClaude.configuration()
                    let args = ["usage", "--provider", "claude", "--source", "web", "--json"]
                    let data = try execute(args, environment: ["CODEXBAR_CONFIG": config.path])
                    guard let row = try parse(data, provider: .claude).first, let reading = row.reading else {
                        throw FeedError.message("Open Claude Desktop and click Connect Claude Desktop to allow its usage reading.")
                    }
                    if let email = reading.identity, accounts.contains(where: { $0.reading?.identity?.caseInsensitiveCompare(email) == .orderedSame }) {
                        return accounts
                    }
                    result = Observation(key: desktop, reading: reading)
                } catch {
                    result = Observation(key: desktop, issue: error.localizedDescription)
                }
                accounts.append(result)
            }
            return accounts
        } catch {
            return [Observation(issue: error.localizedDescription)]
        }
    }

    private static func query(_ provider: Provider, all: Bool) throws -> [Observation] {
        let arguments = ["usage", "--provider", provider.rawValue, "--json"] + (all ? ["--all-accounts"] : [])
        return try parse(execute(arguments), provider: provider)
    }

    static func execute(_ arguments: [String], environment: [String: String] = [:]) throws -> Data {
        let files = FileManager.default
        let home = files.homeDirectoryForCurrentUser.path
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let paths = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.grok/bin", "\(home)/.opencode/bin",
                     "/Applications/CodexBar.app/Contents/Helpers"]
        let bins = paths + envPath.components(separatedBy: ":").filter { $0.hasPrefix("/") }
        let candidates = bins.map { $0 + "/codexbar" } + ["/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI"]
        guard let binary = candidates.first(where: files.isExecutableFile(atPath:)) else {
            throw FeedError.message("Install CodexBar with its CLI to connect automatic usage.")
        }
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        env["PATH"] = bins.joined(separator: ":")
        process.environment = env
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        // A provider can wait on an expired login. Bound each fetch independently.
        let timeout = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        let killTimeout = DispatchWorkItem {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 120, execute: timeout)
        DispatchQueue.global().asyncAfter(deadline: .now() + 123, execute: killTimeout)
        defer { timeout.cancel(); killTimeout.cancel() }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard !data.isEmpty else {
            throw FeedError.message("No response from CodexBar. Check the provider login and refresh.")
        }
        return data
    }
}
