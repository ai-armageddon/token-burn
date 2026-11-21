import SwiftUI
import Combine

struct DependencySetup: View {
    @ObservedObject var store: Store
    let tool: LiveTool
    private let checks = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        let installing = store.installingTool == tool
        let homebrew = store.toolPaths.executable("brew") != nil
        VStack(alignment: .leading, spacing: 12) {
            Text(tool == .codexbar ? "Set up live tracking" : "Set up Claude sign-in")
                .font(.system(size: 19, weight: .semibold))
            Text(tool == .codexbar
                 ? "Token Burn uses CodexBar to read your subscription allowances. You can also enter readings manually."
                 : "Claude Code opens the browser sign-in and keeps this Claude account in its own profile.")
                .font(.callout).foregroundStyle(Color.quiet)
            if let message = store.setupMessage {
                Text(message).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
            } else if homebrew && !installing {
                Text("Installs with Homebrew when you choose Install.").font(.caption).foregroundStyle(Color.quiet)
            } else if !homebrew {
                Text(tool == .codexbar ? "Download CodexBar and move it to Applications. This panel detects it automatically."
                     : "Follow the official Claude Code installation instructions. Sign-in resumes when the CLI is available.")
                    .font(.caption).foregroundStyle(Color.quiet)
            }
            HStack {
                if installing {
                    ProgressView().controlSize(.small)
                    Text("Installing \(tool.name)…").font(.callout)
                } else if homebrew {
                    Button("Install \(tool.name)") { store.installDependency(tool) }
                        .buttonStyle(.borderedProminent).tint(Color.signal)
                        .help("Run brew install --cask \(tool.cask)")
                } else {
                    Link(tool == .codexbar ? "Download CodexBar" : "Get Claude Code", destination: tool.instructions)
                        .buttonStyle(.borderedProminent).tint(Color.signal)
                }
                Spacer()
                Button("Later") { store.dismissSetup() }
            }
            HStack(spacing: 14) {
                Button("Check again") { store.checkSetup(showMissingMessage: true) }
                    .buttonStyle(.link).disabled(installing)
                if homebrew { Link("Official installation page ↗", destination: tool.instructions) }
            }.font(.caption)
            Spacer(minLength: 0)
        }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onReceive(checks) { _ in store.checkSetup() }
    }
}
