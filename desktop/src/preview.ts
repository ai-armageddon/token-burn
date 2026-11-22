// Browser preview for `npm run dev` outside Tauri. Uses the fictional accounts
// from the README screenshots. Query flags: ?setup (CodexBar missing),
// ?windows (WSL runtime), ?nowsl (Windows without WSL).
import { mockIPC, mockWindows } from "@tauri-apps/api/mocks";

const flags = new URLSearchParams(location.search);
const hour = 3_600_000;
const iso = (offset: number) => new Date(Date.now() + offset).toISOString();
const now = iso(0);

const reports: Record<string, unknown[]> = {
  claude: [
    { provider: "claude", account: "ava@example.com", source: "oauth", usage: { accountEmail: "ava@example.com", loginMethod: "Claude Pro", updatedAt: now, primary: { usedPercent: 18, windowMinutes: 300, resetsAt: iso(2.5 * hour) }, secondary: { usedPercent: 41, windowMinutes: 10080, resetsAt: iso(80 * hour) } } },
    { provider: "claude", account: "studio@example.com", source: "oauth", usage: { accountEmail: "studio@example.com", loginMethod: "Claude Max 20x", updatedAt: now, primary: { usedPercent: 86, windowMinutes: 300, resetsAt: iso(0.6 * hour) }, secondary: { usedPercent: 52, windowMinutes: 10080, resetsAt: iso(30 * hour) } } },
  ],
  codex: [
    { provider: "codex", account: "dev@example.com", source: "oauth", usage: { accountEmail: "dev@example.com", planObservation: { rawPlan: "promax" }, updatedAt: now, primary: { usedPercent: 12, windowMinutes: 300, resetsAt: iso(3 * hour) }, secondary: { usedPercent: 37, windowMinutes: 10080, resetsAt: iso(100 * hour) }, codexResetCredits: { credits: [{ title: "Full reset", status: "available", expires_at: iso(240 * hour) }, { title: "Full reset", status: "available", expires_at: iso(500 * hour) }] } } },
  ],
  opencodego: [
    { provider: "opencodego", source: "api", usage: { loginMethod: "Go Plus", updatedAt: now, primary: { usedPercent: 62, windowMinutes: 43200, resetsAt: iso(300 * hour) } } },
  ],
  grok: [
    { provider: "grok", source: "rpc", usage: { loginMethod: "SuperGrok", updatedAt: now, primary: { usedPercent: 8, windowMinutes: 10080, resetsAt: iso(150 * hour) } } },
  ],
};

let installed = !flags.has("setup");
const store: Record<string, string> = {};

mockWindows("deck");
mockIPC(
  async (cmd, payload) => {
    const args = (payload ?? {}) as Record<string, unknown>;
    switch (cmd) {
      case "platform_info":
        return {
          os: flags.has("windows") || flags.has("nowsl") ? "windows" : "linux",
          runtime: flags.has("windows") || flags.has("nowsl") ? "wsl" : "native",
          runtimeAvailable: !flags.has("nowsl"),
          canInstall: !flags.has("windows") && !flags.has("nowsl"),
        };
      case "find_tool":
        return installed ? `/usr/local/bin/${args.name}` : null;
      case "install_codexbar":
        await new Promise((r) => setTimeout(r, 1500));
        installed = true;
        return null;
      case "run_tool": {
        await new Promise((r) => setTimeout(r, 400));
        const list = args.args as string[];
        if (args.name === "claude" && list[0] === "auth") {
          if (list[1] === "login") return { code: 0, stdout: "", timedOut: false };
          const email = (args.env as Record<string, string>).CLAUDE_CONFIG_DIR?.split("/").pop();
          return { code: 0, stdout: JSON.stringify({ loggedIn: true, email: store[`profile:${email}`] }), timedOut: false };
        }
        const provider = list[list.indexOf("--provider") + 1];
        const env = args.env as Record<string, string>;
        if (env.CLAUDE_CONFIG_DIR) {
          const email = store[`profile:${env.CLAUDE_CONFIG_DIR.split("/").pop()}`];
          const row = { provider: "claude", source: "oauth", usage: { accountEmail: email, loginMethod: "Claude Pro", updatedAt: now, primary: { usedPercent: 30, windowMinutes: 300, resetsAt: iso(4 * hour) } } };
          return { code: 0, stdout: JSON.stringify([row]), timedOut: false };
        }
        return { code: 0, stdout: JSON.stringify(reports[provider] ?? []), timedOut: false };
      }
      case "prepare_profile":
        return { CLAUDE_CONFIG_DIR: `/home/preview/.local/share/token-burn/claude-profiles/${args.id}`, CODEXBAR_CONFIG: "/dev/null" };
      case "state_path":
        return "/home/preview/.local/share/app.tokenburn.deck/accounts.json";
      case "load_state":
        return sessionStorage.getItem("preview-state");
      case "save_state":
        sessionStorage.setItem("preview-state", args.contents as string);
        return null;
      default:
        return null;
    }
  },
  { shouldMockEvents: true },
);

// Sign-in in the preview maps each new profile ID to the email it was created for.
const original = Storage.prototype.setItem;
Storage.prototype.setItem = function (key: string, value: string) {
  if (key === "preview-state") {
    for (const account of JSON.parse(value).accounts ?? []) {
      if (account.claudeProfileEmail) store[`profile:${account.id}`] = account.claudeProfileEmail;
    }
  }
  return original.call(this, key, value);
};
