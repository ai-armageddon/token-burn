// Port of Store.swift, ClaudeProfile.swift and UsageFeed.fetch.
import {
  Account, FeedError, Observation, Provider, Reading, SavedState,
  initialState, merge, migrateAccountVisibility, moveBy, moveTo, newAccount, parseUsage, providers, visibleAccounts,
} from "./model";
import { PlatformInfo, Runtime, Tool, errorMessage } from "./native";

export const toolName: Record<Tool, string> = { codexbar: "CodexBar", claude: "Claude Code" };
const DEFERRED = "DeferredCodexBarSetup";

export class Store {
  state: SavedState = initialState();
  refreshing = new Set<Provider>();
  refreshingProfiles = new Set<string>();
  storageIssue: string | null = null;
  needsCodexBar = false;
  setupTool: Tool | null = null;
  installingTool: Tool | null = null;
  setupMessage: string | null = null;
  platform: PlatformInfo = { os: "linux", runtime: "native", runtimeAvailable: true, canInstall: false };

  private pendingSignIn: string | null = null;
  private canSave = true;
  private timer: ReturnType<typeof setInterval> | undefined;
  private listeners = new Set<() => void>();

  constructor(private rt: Runtime) {}

  get visible(): Account[] {
    return visibleAccounts(this.state);
  }

  subscribe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private changed() {
    for (const listener of this.listeners) listener();
  }

  async load() {
    this.platform = await this.rt.platform();
    try {
      const text = await this.rt.loadState();
      if (text) {
        this.state = { ...initialState(), ...JSON.parse(text) };
        migrateAccountVisibility(this.state);
      }
    } catch {
      this.canSave = false;
      this.storageIssue = `Could not load saved accounts. Check ${await this.rt.statePath().catch(() => "accounts.json")} before restarting.`;
    }
    this.changed();
  }

  async start() {
    if ((await this.missing(false)) && this.rt.getPref(DEFERRED) !== "1") this.requestSetup("codexbar");
    await this.refresh();
    this.timer = setInterval(() => void this.refresh(), 300_000);
  }

  stop() {
    clearInterval(this.timer);
  }

  async missing(forClaudeLogin: boolean): Promise<Tool | null> {
    if (!(await this.rt.findTool("codexbar"))) return "codexbar";
    if (forClaudeLogin && !(await this.rt.findTool("claude"))) return "claude";
    return null;
  }

  requestSetup(tool: Tool) {
    this.setupMessage = null;
    this.setupTool = tool;
    this.changed();
  }

  dismissSetup() {
    if (this.setupTool === "codexbar") this.rt.setPref(DEFERRED, "1");
    this.pendingSignIn = null;
    this.setupTool = null;
    this.setupMessage = null;
    this.changed();
  }

  async installDependency(tool: Tool) {
    if (this.installingTool || this.setupTool !== tool || tool !== "codexbar") return;
    if (await this.checkSetup()) return;
    this.installingTool = tool;
    this.setupMessage = null;
    this.changed();
    try {
      await this.rt.installCodexBar();
      this.installingTool = null;
      if (!(await this.checkSetup())) await this.refresh();
    } catch (error) {
      this.installingTool = null;
      if (this.setupTool === tool) this.setupMessage = errorMessage(error);
    }
    this.changed();
  }

  async checkSetup(showMissingMessage = false): Promise<boolean> {
    const tool = this.setupTool;
    if (!tool || this.installingTool) return false;
    if (!(await this.rt.findTool(tool))) {
      if (showMissingMessage && this.setupTool === tool) {
        this.setupMessage = `Still looking for ${toolName[tool]}. Finish installation, then check again.`;
        this.changed();
      }
      return false;
    }
    if (this.setupTool !== tool) return false;
    this.setupTool = null;
    this.setupMessage = null;
    if (tool === "codexbar") this.rt.setPref(DEFERRED, null);
    const pending = this.pendingSignIn && this.state.accounts.find((a) => a.id === this.pendingSignIn);
    if (pending) {
      this.pendingSignIn = null;
      void this.refreshProfile(pending, true);
    }
    this.changed();
    await this.refresh();
    return true;
  }

  async userRefresh() {
    if (this.setupTool) await this.checkSetup(true);
    else if (!(await this.rt.findTool("codexbar"))) this.requestSetup("codexbar");
    else await this.refresh();
  }

  showAccount(id: string) {
    const account = this.state.accounts.find((a) => a.id === id);
    if (!account) return;
    this.update(id, (a) => (a.hidden = false));
    if (account.claudeProfileEmail) void this.refreshProfile(account, false);
  }

  addClaudeProfile(email: string): string {
    const existing = this.state.accounts.find(
      (a) => a.provider === "claude" && (a.claudeProfileEmail ?? a.reading?.identity)?.toLowerCase() === email.toLowerCase(),
    );
    if (existing) {
      this.showAccount(existing.id);
      return existing.id;
    }
    const account = newAccount("claude", { claudeProfileEmail: email });
    this.add(account);
    void this.refreshProfile(account, true);
    return account.id;
  }

  async refreshProfile(account: Account, signIn: boolean) {
    const missing = await this.missing(true);
    if (missing) {
      const issue = `Install ${toolName[missing]} to refresh this login.`;
      if (signIn) {
        this.pendingSignIn = account.id;
        this.requestSetup(missing);
      } else if (account.issue !== issue) {
        this.update(account.id, (a) => (a.issue = issue));
      }
      return;
    }
    if (this.refreshingProfiles.has(account.id)) return;
    this.refreshingProfiles.add(account.id);
    this.changed();
    try {
      const reading = await fetchProfile(this.rt, account, signIn);
      this.update(account.id, (a) => {
        a.reading = reading;
        a.issue = null;
      });
    } catch (error) {
      this.update(account.id, (a) => (a.issue = errorMessage(error)));
    }
    this.refreshingProfiles.delete(account.id);
    this.changed();
  }

  async refresh() {
    this.needsCodexBar = (await this.missing(false)) !== null;
    this.changed();
    if (this.needsCodexBar) return;
    this.rt.setPref(DEFERRED, null);
    const work: Promise<void>[] = providers.map((p) => this.refreshProvider(p));
    for (const account of this.visible) {
      if (account.claudeProfileEmail) work.push(this.refreshProfile(account, false));
    }
    await Promise.all(work);
  }

  private async refreshProvider(provider: Provider) {
    if (this.refreshing.has(provider)) return;
    this.refreshing.add(provider);
    this.changed();
    const result = await fetchProvider(this.rt, provider);
    merge(this.state, result, provider);
    this.refreshing.delete(provider);
    await this.save();
    this.changed();
  }

  move(id: string, target: string): boolean {
    if (!moveTo(this.state, id, target)) return false;
    void this.save();
    this.changed();
    return true;
  }

  moveBy(id: string, step: number) {
    moveBy(this.state, id, step);
    void this.save();
    this.changed();
  }

  setPinned(value: boolean) {
    this.state.pinned = value;
    void this.save();
    this.changed();
  }

  update(id: string, change: (account: Account) => void) {
    const account = this.state.accounts.find((a) => a.id === id);
    if (!account) return;
    change(account);
    void this.save();
    this.changed();
  }

  add(account: Account) {
    this.state.accounts.push(account);
    void this.save();
    this.changed();
  }

  private async save() {
    if (!this.canSave) return;
    try {
      await this.rt.saveState(JSON.stringify(this.state));
      if (this.storageIssue) {
        this.storageIssue = null;
        this.changed();
      }
    } catch {
      this.storageIssue = `Could not save your changes to ${await this.rt.statePath().catch(() => "accounts.json")}.`;
      this.changed();
    }
  }
}

async function execute(rt: Runtime, tool: Tool, args: string[], env: Record<string, string> = {}): Promise<string> {
  const result = await rt.runTool(tool, args, env, 120);
  if (result.stdout.length === 0) throw new FeedError("No response from CodexBar. Check the provider login and refresh.");
  return result.stdout;
}

async function query(rt: Runtime, provider: Provider, all: boolean): Promise<Observation[]> {
  const args = ["usage", "--provider", provider, "--json", ...(all ? ["--all-accounts"] : [])];
  return parseUsage(await execute(rt, "codexbar", args), provider);
}

export async function fetchProvider(rt: Runtime, provider: Provider): Promise<Observation[]> {
  try {
    let accounts = await query(rt, provider, true);
    if (accounts.length === 1 && accounts[0].key == null && /no token accounts configured/i.test(accounts[0].issue ?? "")) {
      accounts = await query(rt, provider, false);
    }
    return accounts;
  } catch (error) {
    return [{ issue: errorMessage(error) }];
  }
}

export async function fetchProfile(rt: Runtime, account: Account, signIn: boolean): Promise<Reading> {
  const email = account.claudeProfileEmail;
  if (!email) throw new FeedError("Choose a Claude account first.");
  const env = await rt.prepareProfile(account.id);
  if (signIn) {
    const login = await rt.runTool("claude", ["auth", "login", "--claudeai", "--email", email], env, 300);
    if (login.code !== 0) throw new FeedError("Claude sign-in did not finish. Try again.");
  }
  let status: Record<string, unknown> | undefined;
  try {
    status = JSON.parse(await execute(rt, "claude", ["auth", "status", "--json"], env));
  } catch (error) {
    if (!(error instanceof SyntaxError)) throw error;
  }
  if (status?.["loggedIn"] !== true || typeof status["email"] !== "string" || status["email"].toLowerCase() !== email.toLowerCase()) {
    throw new FeedError(`Sign in to Claude with ${email} to connect this account.`);
  }
  // OAuth can include saved resets. Only use the reading if its reported owner
  // matches this isolated login; the CLI remains the quota fallback.
  try {
    const reading = await fetchUsage(rt, "oauth", email, env);
    if (reading.source === "oauth") return reading;
  } catch {
    // Fall through to the CLI source.
  }
  return fetchUsage(rt, "cli", email, env);
}

async function fetchUsage(rt: Runtime, source: string, email: string, env: Record<string, string>): Promise<Reading> {
  const report = await execute(rt, "codexbar", ["usage", "--provider", "claude", "--source", source, "--json"], env);
  const rows = parseUsage(report, "claude");
  const reading = rows.flatMap((r) => (r.reading ? [r.reading] : [])).find((r) => r.identity?.toLowerCase() === email.toLowerCase());
  if (!reading) throw new FeedError(rows[0]?.issue ?? `Claude returned no verified allowance for ${email}.`);
  return reading;
}
