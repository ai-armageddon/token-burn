// Port of DependencySetup.swift with Linux and Windows (WSL) instructions.
import { useEffect } from "preact/hooks";
import { Tool } from "../native";
import { Store, toolName } from "../store";
import { Link, open } from "./parts";

const RELEASES = "https://github.com/steipete/CodexBar/releases/latest";
const CLAUDE_SETUP = "https://code.claude.com/docs/en/setup";
const WSL_SETUP = "https://learn.microsoft.com/windows/wsl/install";

export function DependencySetup({ store, tool }: { store: Store; tool: Tool }) {
  useEffect(() => {
    const id = setInterval(() => void store.checkSetup(), 3000);
    return () => clearInterval(id);
  }, [store]);

  const { platform } = store;
  const wsl = platform.runtime === "wsl";
  const noWsl = wsl && !platform.runtimeAvailable;
  const installing = store.installingTool === tool;
  const brew = tool === "codexbar" && platform.canInstall;
  const page = noWsl ? WSL_SETUP : tool === "codexbar" ? RELEASES : CLAUDE_SETUP;

  let guidance: string;
  if (noWsl) {
    guidance = "On Windows, Token Burn runs the CodexBar CLI inside WSL. Run wsl --install, restart, then install CodexBar inside Linux.";
  } else if (tool === "codexbar") {
    guidance = brew
      ? "Installs with Homebrew (brew install steipete/tap/codexbar) when you choose Install."
      : wsl
        ? "Inside WSL, install the CodexBar Linux CLI from its release page or with brew install steipete/tap/codexbar. This panel detects it automatically."
        : "Install the CodexBar CLI from its release page, with brew install steipete/tap/codexbar, or from the AUR (codexbar-cli). This panel detects it automatically.";
  } else {
    guidance = wsl
      ? "Install Claude Code inside WSL with the official instructions. Sign-in resumes when the CLI is available."
      : "Follow the official Claude Code installation instructions. Sign-in resumes when the CLI is available.";
  }

  return (
    <section class="panel setup">
      <h2 class="large">{tool === "codexbar" ? "Set up live tracking" : "Set up Claude sign-in"}</h2>
      <p class="callout quiet">
        {tool === "codexbar"
          ? "Token Burn uses CodexBar to read your subscription allowances. You can also enter readings manually."
          : "Claude Code opens the browser sign-in and keeps this Claude account in its own profile."}
      </p>
      {store.setupMessage ? <p class="caption warn selectable">{store.setupMessage}</p> : <p class="caption quiet">{guidance}</p>}
      <div class="row">
        {installing ? (
          <span class="callout"><span class="spinner" /> Installing {toolName[tool]}…</span>
        ) : brew ? (
          <button type="button" class="prominent" onClick={() => void store.installDependency(tool)}>Install {toolName[tool]}</button>
        ) : (
          <button type="button" class="prominent" onClick={() => open(page)}>
            {noWsl ? "Install WSL" : tool === "codexbar" ? "Download CodexBar" : "Get Claude Code"}
          </button>
        )}
        <span class="grow" />
        <button type="button" class="bordered" onClick={() => store.dismissSetup()}>Later</button>
      </div>
      <div class="row caption">
        <button type="button" class="link" disabled={installing} onClick={() => void store.checkSetup(true)}>Check again</button>
        {brew && <Link href={page}>Official installation page ↗</Link>}
      </div>
    </section>
  );
}
