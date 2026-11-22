// Ported from Tests/TokenBurnTests/DependencyTests.swift, plus fetch fallbacks.
import { afterEach, describe, expect, test } from "vitest";
import { RunOutput, Runtime, Tool } from "./native";
import { Store, fetchProfile, fetchProvider } from "./store";
import { newAccount } from "./model";

function fakeRuntime(tools: Partial<Record<Tool, boolean>>, run: (tool: Tool, args: string[], env: Record<string, string>) => RunOutput = () => ({ code: 0, stdout: "[]", timedOut: false })) {
  const prefs = new Map<string, string>();
  let saved: string | null = null;
  const calls: string[][] = [];
  const rt: Runtime = {
    platform: async () => ({ os: "linux", runtime: "native", runtimeAvailable: true, canInstall: false }),
    findTool: async (name) => (tools[name] ? `/usr/bin/${name}` : null),
    runTool: async (name, args, env) => {
      calls.push([name, ...args]);
      return run(name, args, env);
    },
    prepareProfile: async (id) => ({ CLAUDE_CONFIG_DIR: `/profiles/${id}`, CODEXBAR_CONFIG: `/profiles/${id}/usage-source.json` }),
    installCodexBar: async () => {
      tools.codexbar = true;
    },
    statePath: async () => "/state/accounts.json",
    loadState: async () => saved,
    saveState: async (text) => {
      saved = text;
    },
    getPref: (key) => prefs.get(key) ?? null,
    setPref: (key, value) => (value === null ? prefs.delete(key) : prefs.set(key, value)),
  };
  return { rt, calls, tools };
}

const stores: Store[] = [];
afterEach(() => stores.splice(0).forEach((s) => s.stop()));
async function started(rt: Runtime) {
  const store = new Store(rt);
  stores.push(store);
  await store.load();
  await store.start();
  return store;
}

describe("dependency setup", () => {
  test("missing tool prompts once and can be reopened", async () => {
    const { rt } = fakeRuntime({});
    const first = await started(rt);
    expect(first.setupTool).toBe("codexbar");
    expect(first.needsCodexBar).toBe(true);
    expect(first.refreshing.size).toBe(0);
    first.dismissSetup();
    const next = await started(rt);
    expect(next.setupTool).toBeNull();
    await next.userRefresh();
    expect(next.setupTool).toBe("codexbar");
    expect(await next.checkSetup(true)).toBe(false);
    expect(next.setupMessage).toBeTruthy();
  });

  test("install clears setup and refreshes", async () => {
    const { rt, calls } = fakeRuntime({});
    const store = await started(rt);
    await store.installDependency("codexbar");
    expect(store.setupTool).toBeNull();
    expect(store.needsCodexBar).toBe(false);
    expect(calls.some((c) => c[0] === "codexbar" && c.includes("--all-accounts"))).toBe(true);
  });

  test("Claude login waits for Claude Code, then resumes", async () => {
    const tools: Partial<Record<Tool, boolean>> = { codexbar: true };
    const { rt } = fakeRuntime(tools);
    const store = await started(rt);
    store.addClaudeProfile("ava@example.com");
    await new Promise((r) => setTimeout(r, 0));
    expect(store.setupTool).toBe("claude");
    expect(await store.checkSetup(true)).toBe(false);
  });
});

describe("fetching", () => {
  test("falls back to the active login when no token accounts are configured", async () => {
    const { rt, calls } = fakeRuntime({ codexbar: true }, (_tool, args) => ({
      code: 0,
      timedOut: false,
      stdout: args.includes("--all-accounts")
        ? `[{"provider":"codex","error":{"message":"No token accounts configured"}}]`
        : `[{"provider":"codex","usage":{"primary":{"usedPercent":10}}}]`,
    }));
    const rows = await fetchProvider(rt, "codex");
    expect(rows[0].reading?.meters[0].percent).toBe(10);
    expect(calls).toHaveLength(2);
  });

  test("empty output becomes a readable issue", async () => {
    const { rt } = fakeRuntime({ codexbar: true }, () => ({ code: null, stdout: "", timedOut: true }));
    expect((await fetchProvider(rt, "grok"))[0].issue).toMatch(/No response from CodexBar/);
  });

  test("profile reading must match the signed-in email, with CLI fallback", async () => {
    const seen: string[] = [];
    const { rt } = fakeRuntime({ codexbar: true, claude: true }, (tool, args, env) => {
      expect(env.CLAUDE_CONFIG_DIR).toMatch(/^\/profiles\//);
      if (tool === "claude") return { code: 0, timedOut: false, stdout: `{"loggedIn":true,"email":"Ava@Example.com"}` };
      const source = args[args.indexOf("--source") + 1];
      seen.push(source);
      const email = source === "oauth" ? "someone@else.com" : "ava@example.com";
      return { code: 0, timedOut: false, stdout: `[{"provider":"claude","source":"${source}","usage":{"accountEmail":"${email}","primary":{"usedPercent":5}}}]` };
    });
    const reading = await fetchProfile(rt, newAccount("claude", { claudeProfileEmail: "ava@example.com" }), false);
    expect(seen).toEqual(["oauth", "cli"]);
    expect(reading.source).toBe("cli");
  });

  test("a different signed-in Claude account is rejected", async () => {
    const { rt } = fakeRuntime({ codexbar: true, claude: true }, () => ({ code: 0, timedOut: false, stdout: `{"loggedIn":true,"email":"other@example.com"}` }));
    await expect(fetchProfile(rt, newAccount("claude", { claudeProfileEmail: "ava@example.com" }), false)).rejects.toThrow(/Sign in to Claude with ava@example.com/);
  });
});
