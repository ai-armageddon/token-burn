// Data model shared with the macOS app (Sources/TokenBurn). Keep the rules in
// sync: Usage.swift, Store.swift (SavedState), BankedResets.swift,
// Subscription.swift and ResetCountdown.swift.

export const providers = ["claude", "codex", "opencodego", "grok"] as const;
export type Provider = (typeof providers)[number];

export const providerName: Record<Provider, string> = {
  claude: "Claude",
  codex: "Codex",
  opencodego: "OpenCode",
  grok: "Grok",
};

export const dashboard: Record<Provider, string> = {
  claude: "https://claude.ai/settings/usage",
  codex: "https://chatgpt.com/codex/settings/usage",
  opencodego: "https://opencode.ai/console",
  grok: "https://grok.com/dashboard",
};

/** Dates are epoch milliseconds so saved state stays plain JSON. */
export interface Meter {
  id: string;
  title: string;
  percent: number;
  reset?: number | null;
}

export interface Grant {
  title: string;
  expiry?: number | null;
}

export interface BankedResets {
  grants: Grant[];
  // Some providers publish only a total and the earliest expiry.
  reportedCount?: number | null;
  nextExpiry?: number | null;
  expiryNote?: string | null;
}

export interface Reading {
  meters: Meter[];
  updated: number;
  identity?: string | null;
  plan?: string | null;
  source: string;
  estimated: boolean;
  bankedResets?: BankedResets | null;
}

export interface Account {
  id: string;
  provider: Provider;
  key?: string | null;
  label: string;
  manual: boolean;
  hidden: boolean;
  preferred: string;
  reading?: Reading | null;
  issue?: string | null;
  claudeProfileEmail?: string | null;
  customTier?: string | null;
  customPrice?: string | null;
}

export interface Observation {
  key?: string | null;
  reading?: Reading | null;
  issue?: string | null;
}

export interface SavedState {
  accounts: Account[];
  pinned: boolean;
  accountOrder?: string[] | null;
  explicitExtraAccounts?: boolean | null;
}

export class FeedError extends Error {}

export function uuid(): string {
  return crypto.randomUUID();
}

export function newAccount(provider: Provider, fields: Partial<Account> = {}): Account {
  return { id: uuid(), provider, label: "", manual: false, hidden: false, preferred: "", ...fields };
}

export function initialState(): SavedState {
  return { accounts: providers.map((p) => newAccount(p)), pinned: true, explicitExtraAccounts: true };
}

// MARK: Meters

export const remaining = (m: Meter) => Math.min(100, Math.max(0, 100 - m.percent));
export const isLow = (m: Meter) => remaining(m) < 20;
export function remainingText(m: Meter): string {
  const r = remaining(m);
  if (r > 0 && r < 1) return "<1%";
  return `${Math.round(r)}%`;
}

// MARK: Account helpers

export function meterOf(a: Account): Meter | undefined {
  const meters = a.reading?.meters ?? [];
  return meters.find((m) => m.id === a.preferred) ?? meters[0];
}

/** Keep the selected window outside and show one other standard allowance inside. */
export function innerMeter(a: Account): Meter | undefined {
  const outer = meterOf(a);
  return a.reading?.meters.find((m) => m.id !== outer?.id && ["primary", "secondary", "tertiary"].includes(m.id));
}

export const isDesktopClaude = (a: Account) => a.provider === "claude" && !!a.key?.startsWith("claude-desktop:");
export const accountName = (a: Account) => (a.label ? a.label : providerName[a.provider]);
export function accountLabel(a: Account): string | undefined {
  if (isDesktopClaude(a)) return a.reading?.identity ?? "Claude Desktop";
  return a.claudeProfileEmail ?? a.key ?? undefined;
}

export function isStale(a: Account, now = Date.now()): boolean {
  const reading = a.reading;
  if (!reading) return false;
  const reset = meterOf(a)?.reset;
  if (reset != null && reset <= now) return true;
  return !a.manual && (a.issue != null || now - reading.updated > 660_000);
}

// MARK: Banked resets

export const formatDateTime = (ms: number) =>
  new Date(ms).toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" });

export function bankDates(bank: BankedResets): number[] {
  return [...bank.grants.flatMap((g) => (g.expiry != null ? [g.expiry] : [])), ...(bank.nextExpiry != null ? [bank.nextExpiry] : [])];
}

export function bankAvailable(bank: BankedResets, now: number): { count: number; lines: string[] } {
  if (bank.reportedCount != null) {
    if (bank.nextExpiry != null && bank.nextExpiry <= now) return { count: 0, lines: [] };
    const next = bank.nextExpiry != null ? "Next expiry · " + formatDateTime(bank.nextExpiry) : undefined;
    return { count: bank.reportedCount, lines: [next ?? bank.expiryNote ?? "Expiry unavailable"] };
  }
  const active = bank.grants
    .filter((g) => (g.expiry ?? Infinity) > now)
    .sort((a, b) => (a.expiry ?? Infinity) - (b.expiry ?? Infinity));
  return {
    count: active.length,
    lines: active.map((g) => g.title + " · " + (g.expiry != null ? "Expires " + formatDateTime(g.expiry) : "Expiry unavailable")),
  };
}

type Fields = Record<string, unknown>;
const isFields = (v: unknown): v is Fields => typeof v === "object" && v !== null && !Array.isArray(v);
const fieldsArray = (v: unknown): Fields[] => (Array.isArray(v) ? v.filter(isFields) : []);
const str = (v: unknown): string | undefined => (typeof v === "string" ? v : undefined);
const int = (v: unknown): number | undefined => (typeof v === "number" && Number.isInteger(v) ? v : undefined);

export function parseDate(value: unknown): number | undefined {
  if (typeof value !== "string") return undefined;
  // ISO 8601 with a zone, optionally with fractional seconds, matching the Swift reader.
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:?\d{2})$/.test(value)) return undefined;
  const ms = Date.parse(value);
  return Number.isNaN(ms) ? undefined : ms;
}

export function parseBank(usage: Fields, entry: Fields, provider: Provider): BankedResets | undefined {
  if (provider === "codex") {
    const inventory = usage["codexResetCredits"];
    if (isFields(inventory) && Array.isArray(inventory["credits"])) {
      const grants: Grant[] = [];
      for (const item of fieldsArray(inventory["credits"])) {
        if (item["status"] !== "available") continue;
        const expiry = parseDate(item["expires_at"]);
        if (typeof item["expires_at"] === "string" && expiry === undefined) continue;
        grants.push({ title: str(item["title"]) ?? "Full reset", expiry: expiry ?? null });
      }
      return { grants };
    }
    const summary = entry["resetCredits"];
    if (isFields(summary)) {
      const count = int(summary["available"]);
      if (count !== undefined && count > 0) {
        return { grants: [], reportedCount: count, nextExpiry: parseDate(summary["nextExpiresAt"]) ?? null };
      }
    }
  }
  if (provider === "claude") {
    for (const section of fieldsArray(usage["details"])) {
      for (const row of fieldsArray(section["rows"])) {
        if (row["label"] !== "Limit Reset Credits") continue;
        const value = str(row["value"]);
        const word = value?.split(" ").filter(Boolean)[0];
        if (!word || !/^[+-]?\d+$/.test(word)) continue;
        const count = parseInt(word, 10);
        if (count < 1 || count > 50) continue;
        return { grants: [], reportedCount: count, expiryNote: str(row["secondaryValue"]) ?? null };
      }
    }
  }
  return undefined;
}

export function claudeResetNote(a: Account): string | undefined {
  const reading = a.reading;
  if (a.provider !== "claude" || a.manual || !reading || reading.bankedResets) return undefined;
  switch (reading.source.toLowerCase()) {
    case "claude":
    case "cli":
      return "Banked resets unavailable from the Claude CLI.";
    default:
      return "Claude did not report a banked-reset count in this reading.";
  }
}

// MARK: Usage feed

export function parseUsage(text: string, provider: Provider, now = Date.now()): Observation[] {
  let entries: unknown;
  try {
    entries = JSON.parse(text);
  } catch {
    entries = undefined;
  }
  if (!Array.isArray(entries) || !entries.every(isFields)) {
    throw new FeedError("CodexBar returned an unreadable usage report.");
  }
  const observations = (entries as Fields[])
    .filter((e) => e["provider"] === provider)
    .map((entry): Observation => {
      const usage = isFields(entry["usage"]) ? entry["usage"] : {};
      const identity = isFields(usage["identity"]) ? usage["identity"] : {};
      const email = str(usage["accountEmail"]) ?? str(identity["accountEmail"]);
      const key = str(entry["account"]) ?? email;
      const labels = isFields(entry["rateWindowLabels"]) ? entry["rateWindowLabels"] : {};
      const meter = (raw: unknown, id: string, title: string | undefined): Meter | undefined => {
        if (!isFields(raw)) return undefined;
        const n = raw["usedPercent"];
        if (typeof n !== "number" || !Number.isFinite(n) || n < 0 || n > 100) return undefined;
        const fallback =
          ({ 300: "5-hour window", 10080: "Weekly", 43200: "Monthly" } as Record<number, string>)[int(raw["windowMinutes"]) ?? -1] ??
          "Usage window";
        return { id, title: title ?? fallback, percent: n, reset: parseDate(raw["resetsAt"]) ?? null };
      };
      const meters: Meter[] = [];
      for (const id of ["primary", "secondary", "tertiary"]) {
        const m = meter(usage[id], id, str(labels[id]));
        if (m) meters.push(m);
      }
      for (const item of fieldsArray(usage["extraRateWindows"])) {
        const id = str(item["id"]);
        const extra = id ? meter(item["window"], id, str(item["title"])) : undefined;
        if (extra) meters.push(extra);
      }
      const error = entry["error"];
      const message = isFields(error) ? str(error["message"]) : undefined;
      if (message !== undefined) return { key, issue: message };
      const bank = parseBank(usage, entry, provider);
      if (meters.length === 0 && (bank ? bankAvailable(bank, now).count : 0) === 0) {
        return { key, issue: "No usage window was reported for this account." };
      }
      const source = str(entry["source"]) ?? "provider";
      const plan =
        str(isFields(usage["planObservation"]) ? usage["planObservation"]["rawPlan"] : undefined) ??
        str(usage["loginMethod"]) ??
        str(identity["loginMethod"]);
      const reading: Reading = {
        meters,
        updated: parseDate(usage["updatedAt"]) ?? now,
        identity: email ?? key ?? null,
        plan: plan ?? null,
        source,
        estimated: usage["dataConfidence"] === "estimated" || (provider === "opencodego" && source === "local"),
        bankedResets: bank ?? null,
      };
      return { key, reading };
    });
  if (observations.length === 0) throw new FeedError("CodexBar returned no accounts.");
  return observations;
}

// MARK: Saved state (mutating helpers, mirroring SavedState in Store.swift)

export function visibleAccounts(state: SavedState): Account[] {
  const grouped = providers.flatMap((p) => state.accounts.filter((a) => a.provider === p && !a.hidden));
  if (!state.accountOrder) return grouped;
  const byID = new Map(grouped.map((a) => [a.id, a]));
  const known = new Set(state.accountOrder);
  return [
    ...state.accountOrder.flatMap((id) => (byID.has(id) ? [byID.get(id)!] : [])),
    ...grouped.filter((a) => !known.has(a.id)),
  ];
}

export function moveTo(state: SavedState, id: string, target: string): boolean {
  const visible = visibleAccounts(state).map((a) => a.id);
  const from = visible.indexOf(id);
  const to = visible.indexOf(target);
  if (id === target || from < 0 || to < 0) return false;
  visible.splice(from, 1);
  visible.splice(to, 0, id);
  const order = state.accountOrder ? [...state.accountOrder] : providers.flatMap((p) => state.accounts.filter((a) => a.provider === p).map((a) => a.id));
  const known = new Set(order);
  order.push(...visible.filter((v) => !known.has(v)));
  const visibleIDs = new Set(visible);
  // Replace visible slots in sequence so hidden accounts retain their saved positions.
  let next = 0;
  state.accountOrder = order.map((o) => (visibleIDs.has(o) ? (visible[next++] ?? o) : o));
  return true;
}

export function moveBy(state: SavedState, id: string, step: number): void {
  const ids = visibleAccounts(state).map((a) => a.id);
  const position = ids.indexOf(id);
  if (position < 0 || position + step < 0 || position + step >= ids.length) return;
  moveTo(state, id, ids[position + step]);
}

export function migrateAccountVisibility(state: SavedState): void {
  if (state.explicitExtraAccounts === true) return;
  const primary = new Set<Provider>();
  for (const a of state.accounts) {
    if (a.manual) continue;
    if (primary.has(a.provider)) a.hidden = true;
    else primary.add(a.provider);
  }
  state.explicitExtraAccounts = true;
}

export function merge(state: SavedState, observations: Observation[], provider: Provider): void {
  const accounts = state.accounts;
  const existing = accounts.filter((a) => a.provider === provider && !a.manual && a.claudeProfileEmail == null);
  if (observations.length === 1 && observations[0].key == null && observations[0].reading == null) {
    for (const a of existing) a.issue = observations[0].issue ?? null;
    return;
  }
  const seen = new Set<string>();
  for (const o of observations) {
    if (o.key == null && o.reading == null) {
      for (const a of existing) {
        if (isDesktopClaude(a)) continue;
        a.issue = o.issue ?? null;
        seen.add(a.id);
      }
      continue;
    }
    const match = existing.find((a) => (a.key ?? null) === (o.key ?? null));
    const empty = existing.find((a) => a.key == null && a.reading == null && !seen.has(a.id));
    let account = match ?? empty;
    if (!account) {
      account = newAccount(provider, { hidden: true });
      accounts.push(account);
    }
    account.key = o.key ?? null;
    if (o.reading) account.reading = o.reading;
    account.issue = o.issue ?? null;
    seen.add(account.id);
  }
  for (const a of existing) {
    if (!seen.has(a.id)) a.issue = "This account was absent from the latest refresh. Check its login in CodexBar.";
  }
}

// MARK: Reset countdown

export type Proximity = "unknown" | "due" | "withinHour" | "withinSixHours" | "withinDay" | "later";

const oneDecimal = (n: number) => new Intl.NumberFormat(undefined, { maximumFractionDigits: 1 }).format(n);

export function resetCountdown(reset: number | null | undefined, now: number): { proximity: Proximity; text: string; compactText: string } {
  if (reset == null) return { proximity: "unknown", text: "—", compactText: "—" };
  const seconds = (reset - now) / 1000;
  if (seconds <= 0) return { proximity: "due", text: "due", compactText: "due" };
  const proximity: Proximity = seconds <= 3600 ? "withinHour" : seconds <= 21600 ? "withinSixHours" : seconds <= 86400 ? "withinDay" : "later";
  const minutes = Math.ceil(seconds / 60);
  const hours = Math.floor(minutes / 60);
  const days = Math.floor(hours / 24);
  if (seconds < 60) return { proximity, text: "<1m", compactText: "<1m" };
  if (hours === 0) return { proximity, text: `${minutes}m`, compactText: `${minutes}m` };
  if (days === 0) {
    const rest = minutes % 60;
    return { proximity, text: rest === 0 ? `${hours}h` : `${hours}h ${rest}m`, compactText: oneDecimal(seconds / 3600) + "h" };
  }
  const rest = hours % 24;
  return { proximity, text: rest === 0 ? `${days}d` : `${days}d ${rest}h`, compactText: oneDecimal(seconds / 86400) + "d" };
}

// MARK: List prices (US web list rates checked November 20, 2026)

export interface ListPlan {
  name: string;
  dollars: number;
  source: string;
}

export function lookupPlan(raw: string, provider: Provider): ListPlan | undefined {
  const key = raw.toLowerCase().replace(/[^\p{L}\p{N}]/gu, "");
  const table: Record<Provider, { url: (k: string) => string; rates: Record<string, [string, number]> }> = {
    claude: {
      url: () => "https://support.claude.com/en/articles/11049762-choose-a-claude-plan",
      rates: {
        claudemax20x: ["Max 20x", 200], max20x: ["Max 20x", 200],
        claudemax5x: ["Max 5x", 100], max5x: ["Max 5x", 100],
        claudepro: ["Pro", 20], pro: ["Pro", 20],
        claudefree: ["Free", 0], free: ["Free", 0],
      },
    },
    codex: {
      url: (k) =>
        ["go", "chatgptgo", "plus", "chatgptplus", "free"].includes(k)
          ? "https://openai.com/index/introducing-chatgpt-go/"
          : "https://help.openai.com/en/articles/9793128-about-chatgpt-pro-tiers",
      rates: {
        free: ["Free", 0], go: ["Go", 8], chatgptgo: ["Go", 8],
        plus: ["Plus", 20], chatgptplus: ["Plus", 20],
        promax: ["Pro 500", 500], pro500: ["Pro 500", 500], chatgptpro500: ["Pro 500", 500],
        pro200: ["Pro 200", 200], chatgptpro200: ["Pro 200", 200],
        prolite: ["Pro 100", 100], pro100: ["Pro 100", 100], chatgptpro100: ["Pro 100", 100],
      },
    },
    grok: {
      url: () => "https://x.ai/pricing",
      rates: { supergrok: ["SuperGrok", 30], supergrokplus: ["SuperGrok Plus", 100] },
    },
    opencodego: {
      url: () => "https://opencode.ai/docs/console/go/",
      rates: { go: ["Go", 10], opencodego: ["Go", 10], goplus: ["Go Plus", 40], opencodegoplus: ["Go Plus", 40] },
    },
  };
  const entry = table[provider];
  const rate = Object.hasOwn(entry.rates, key) ? entry.rates[key] : undefined;
  return rate && { name: rate[0], dollars: rate[1], source: entry.url(key) };
}

export const tierOf = (a: Account) => a.customTier ?? a.reading?.plan ?? undefined;
export const listPlan = (a: Account) => {
  const tier = tierOf(a);
  return tier ? lookupPlan(tier, a.provider) : undefined;
};
export const tierName = (a: Account) => listPlan(a)?.name ?? tierOf(a);
export function priceText(a: Account): string | undefined {
  if (a.customPrice != null) return a.customPrice;
  const plan = listPlan(a);
  return plan && `$${plan.dollars}/mo list`;
}

/** Accept a single billed amount; mixed or ambiguous descriptions keep their full text in details. */
export function badgeAmount(a: Account): number | undefined {
  if (a.customPrice == null) return listPlan(a)?.dollars;
  const price = a.customPrice.trim();
  const match = /^(?:[A-Za-z]{3}\s*|US)?[$€£¥₹]?\s*([0-9]+(?:\.[0-9]{1,2})?)\s*(?:[A-Za-z]{3}\b)?(?:\s*(?:\/|per\s+)\s*[A-Za-z]+)?$/i.exec(price);
  return match ? Number(match[1]) : undefined;
}

export function priceDetail(a: Account): string {
  if (a.customPrice != null) return `${a.customPrice} · Entered by you`;
  const plan = listPlan(a);
  if (plan) return `US$${plan.dollars}/month · US web list price`;
  return "Price unavailable · Set your price in Edit account";
}
