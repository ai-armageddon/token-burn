import Foundation

enum LiveTool: String {
    case codexbar, claude
    var name: String { self == .codexbar ? "CodexBar" : "Claude Code" }
    var cask: String { self == .codexbar ? "codexbar" : "claude-code" }
    var instructions: URL {
        self == .codexbar ? URL(string: "https://github.com/steipete/CodexBar/releases/latest")!
                          : URL(string: "https://code.claude.com/docs/en/setup")!
    }
}

struct ToolPaths {
    let bins: [String]
    let helpers: [String]
    static var system: Self {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return Self(bins: ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.grok/bin", "\(home)/.opencode/bin"]
                    + path.components(separatedBy: ":").filter { $0.hasPrefix("/") },
                    helpers: ["/Applications", "\(home)/Applications"].map { $0 + "/CodexBar.app/Contents/Helpers/CodexBarCLI" })
    }

    func executable(_ name: String) -> String? {
        let candidates = bins.map { $0 + "/" + name } + (name == "codexbar" ? helpers : [])
        return candidates.first {
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: $0, isDirectory: &directory) && !directory.boolValue &&
                FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    func missing(forClaudeLogin: Bool) -> LiveTool? {
        if executable("codexbar") == nil { return .codexbar }
        if forClaudeLogin && executable("claude") == nil { return .claude }
        return nil
    }

    func install(_ tool: LiveTool) throws {
        if executable(tool.rawValue) != nil { return }
        guard let brew = executable("brew") else { throw FeedError.message("Open the official installation page below.") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: brew)
        process.arguments = ["install", "--cask", tool.cask]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = bins.joined(separator: ":")
        env["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
        env["HOMEBREW_NO_AUTOREMOVE"] = "1"
        env["NONINTERACTIVE"] = "1"
        process.environment = env
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0, executable(tool.rawValue) != nil else {
            throw FeedError.message("Homebrew could not finish installing \(tool.name). Use the installation page below or run brew install --cask \(tool.cask) in Terminal.")
        }
    }
}
