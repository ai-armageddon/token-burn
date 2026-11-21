import Foundation
import Testing
@testable import TokenBurn

struct DependencyTests {
    @Test @MainActor func missingToolPromptsOnceAndCanBeReopened() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: folder)
            defaults.removePersistentDomain(forName: suite)
        }
        let paths = ToolPaths(bins: [], helpers: [])
        let first = Store(toolPaths: paths, defaults: defaults, stateDirectory: folder)
        first.start()
        #expect(first.setupTool == .codexbar)
        #expect(first.needsCodexBar)
        #expect(first.refreshing.isEmpty)
        first.dismissSetup()
        let next = Store(toolPaths: paths, defaults: defaults, stateDirectory: folder)
        next.start()
        #expect(next.setupTool == nil)
        next.userRefresh()
        #expect(next.setupTool == .codexbar)
        #expect(!next.checkSetup(showMissingMessage: true))
        #expect(next.setupMessage != nil)
    }

    @Test func installVerifiesTheExecutableAndOnlyInstallsTheRequestedCask() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let paths = ToolPaths(bins: [folder.path], helpers: [])
        func executable(_ name: String, _ body: String) throws {
            let file = folder.appendingPathComponent(name)
            try body.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        }
        #expect(paths.missing(forClaudeLogin: true) == .codexbar)
        try executable("brew", "#!/bin/sh\nexit 0\n")
        #expect(throws: FeedError.self) { try paths.install(.codexbar) }
        try executable("brew", """
        #!/bin/sh
        [ "$1" = install ] && [ "$2" = --cask ] && [ "$#" -eq 3 ] || exit 1
        case "$3" in
          codexbar) tool=codexbar ;;
          claude-code) tool=claude ;;
          *) exit 1 ;;
        esac
        /usr/bin/touch "${0%/*}/$tool" && /bin/chmod 700 "${0%/*}/$tool"
        """)
        try paths.install(.codexbar)
        #expect(paths.missing(forClaudeLogin: false) == nil)
        #expect(paths.missing(forClaudeLogin: true) == .claude)
        try paths.install(.claude)
        #expect(paths.missing(forClaudeLogin: true) == nil)
        try executable("brew", "#!/bin/sh\nexit 9\n")
        try paths.install(.codexbar)
        let bundleOnly = ToolPaths(bins: [], helpers: [folder.appendingPathComponent("codexbar").path])
        #expect(bundleOnly.missing(forClaudeLogin: false) == nil)
    }
}
