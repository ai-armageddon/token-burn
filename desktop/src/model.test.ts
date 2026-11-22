// Ported from Tests/TokenBurnTests/UsageTests.swift so both apps share behavior.
import { describe, expect, test } from "vitest";
import {
  Account, Meter, Observation, Provider, SavedState,
  accountName, badgeAmount, bankAvailable, claudeResetNote, initialState, innerMeter, isLow, isStale,
  merge, meterOf, migrateAccountVisibility, moveBy, moveTo, newAccount, parseDate, parseUsage,
  priceText, remainingText, resetCountdown, tierName, visibleAccounts,
} from "./model";

const read = (json: string, provider: Provider = "claude") => parseUsage(json, provider);
const roundTrip = (state: SavedState): SavedState => JSON.parse(JSON.stringify(state));
const meter = (percent: number): Meter => ({ id: "w", title: "W", percent });

describe("usage feed", () => {
  test("missing primary and estimated OpenCode", () => {
    const rows = read(`[{"provider":"opencodego","source":"local","usage":{"primary":null,"secondary":{"usedPercent":0,"windowMinutes":10080,"resetsAt":"2026-11-23T13:00:00.000Z"}}}]`, "opencodego");
    const reading = rows[0].reading!;
    expect(reading.estimated).toBe(true);
    expect(reading.meters.map((m) => m.title)).toEqual(["Weekly"]);
    expect(reading.meters[0].percent).toBe(0);
    expect(reading.meters[0].reset).not.toBeNull();
  });

  test("duplicate provider keeps customizations and cache through errors", () => {
    const data = `[{"account":"studio","provider":"claude","usage":{"primary":{"usedPercent":17},"extraRateWindows":[{"id":"model","title":"Model","window":{"usedPercent":32}}]}},{"account":"home","provider":"claude","usage":{"primary":{"usedPercent":62}}}]`;
    const observations = read(data);
    const state = initialState();
    merge(state, observations, "claude");
    const first = state.accounts.find((a) => a.key === "studio")!;
    first.label = "Paid";
    first.preferred = "model";
    const homeID = state.accounts.find((a) => a.key === "home")!.id;
    merge(state, [...observations].reverse(), "claude");
    merge(state, [{ key: "studio", issue: "Sign in" }], "claude");
    expect(state.accounts.filter((a) => a.provider === "claude")).toHaveLength(2);
    expect(accountName(first)).toBe("Paid");
    expect(meterOf(first)?.percent).toBe(32);
    expect(isStale(first)).toBe(true);
    expect(state.accounts.find((a) => a.id === homeID)!.issue).toBeTruthy();
    merge(state, observations, "claude");
    expect(first.issue).toBeNull();
  });

  test("anonymous error and unavailable do not invent zero or overwrite manual", () => {
    const state = initialState();
    const manual = newAccount("claude", { label: "Personal", manual: true });
    state.accounts.push(manual);
    merge(state, read(`[{"provider":"claude","error":{"message":"Sign in first"}}]`), "claude");
    expect(meterOf(state.accounts[0])).toBeUndefined();
    expect(state.accounts.at(-1)!.issue ?? null).toBeNull();
    const bad = read(`[{"provider":"claude","usage":{"primary":{"usedPercent":-5}}}]`);
    expect(bad[0].reading).toBeUndefined();
    expect(roundTrip(state).accounts.at(-1)!.id).toBe(manual.id);
  });

  test("discovered extras stay off the widget until added", () => {
    const rows = read(`[{"provider":"claude","account":"home","usage":{"primary":{"usedPercent":2}}},{"provider":"claude","account":"work","usage":{"primary":{"usedPercent":14}}}]`);
    const state = initialState();
    merge(state, rows, "claude");
    const extra = state.accounts.find((a) => a.key === "work")!;
    expect(state.accounts.filter((a) => a.provider === "claude" && !a.hidden)).toHaveLength(1);
    expect(extra.hidden).toBe(true);
    extra.hidden = false;
    merge(state, [...rows].reverse(), "claude");
    expect(roundTrip(state).accounts.filter((a) => a.provider === "claude" && !a.hidden)).toHaveLength(2);
  });

  test("migrate existing automatic duplicates once", () => {
    const original = initialState();
    original.accounts.push(newAccount("claude", { key: "claude-desktop:second" }));
    original.accounts.push(newAccount("claude", { label: "Manual", manual: true }));
    original.explicitExtraAccounts = null;
    const migrated = roundTrip(original);
    migrateAccountVisibility(migrated);
    expect(migrated.accounts[4].hidden).toBe(true);
    expect(migrated.accounts[5].hidden).toBe(false);
    migrated.accounts[4].hidden = false;
    migrateAccountVisibility(migrated);
    expect(migrated.accounts[4].hidden).toBe(false);
  });

  test("concentric rings use distinct measured windows", () => {
    const rows = read(`[{"provider":"claude","usage":{"primary":{"usedPercent":2},"secondary":{"usedPercent":8}}}]`);
    const account = newAccount("claude", { reading: rows[0].reading });
    expect(remainingText(meterOf(account)!)).toBe("98%");
    expect(remainingText(innerMeter(account)!)).toBe("92%");
    account.preferred = "secondary";
    expect(innerMeter(account)?.id).toBe("primary");
    account.reading!.meters.shift();
    expect(innerMeter(account)).toBeUndefined();
  });

  test("reset countdown uses the clock and exact band boundaries", () => {
    const now = 1_778_000_000_000;
    const c = (s: number) => resetCountdown(now + s * 1000, now);
    expect(resetCountdown(null, now).proximity).toBe("unknown");
    expect(c(-60).text).toBe("due");
    expect(c(0).proximity).toBe("due");
    expect(c(12).text).toBe("<1m");
    expect(c(60).text).toBe("1m");
    expect(c(3600).proximity).toBe("withinHour");
    expect(c(3601).proximity).toBe("withinSixHours");
    expect(c(5400).text).toBe("1h 30m");
    expect(c(21600).proximity).toBe("withinSixHours");
    expect(c(21601).proximity).toBe("withinDay");
    expect(c(86400).proximity).toBe("withinDay");
    expect(c(86401).proximity).toBe("later");
    expect(c(180000).text).toBe("2d 2h");
    expect(c(172800).compactText).toBe("2d");
  });

  test("low ring starts below twenty percent remaining", () => {
    for (const [used, low] of [[79.9, false], [80, false], [80.1, true], [100, true]] as const) {
      expect(isLow({ id: "w", title: "Weekly", percent: used })).toBe(low);
    }
  });

  test("tier pricing follows the account and survives refresh", () => {
    const rows = read(`[{"provider":"codex","usage":{"planObservation":{"rawPlan":"promax"},"secondary":{"usedPercent":7},"providerCost":{"used":18,"limit":30}}}]`, "codex");
    const state = initialState();
    merge(state, rows, "codex");
    const index = state.accounts.findIndex((a) => a.provider === "codex");
    expect(tierName(state.accounts[index])).toBe("Pro 500");
    expect(priceText(state.accounts[index])).toBe("$500/mo list");
    state.accounts[index].customPrice = "€450/year";
    merge(state, rows, "codex");
    expect(priceText(roundTrip(state).accounts[index])).toBe("€450/year");
    const openCode = newAccount("opencodego");
    expect(priceText(openCode)).toBeUndefined();
    openCode.customTier = "Go Plus";
    expect(priceText(openCode)).toBe("$40/mo list");
    openCode.customTier = "Custom";
    expect(priceText(openCode)).toBeUndefined();
  });

  test("custom order survives refresh and hidden accounts", () => {
    const state = initialState();
    const second = newAccount("claude", { claudeProfileEmail: "second@example.com" });
    state.accounts.push(second);
    const original = visibleAccounts(state).map((a) => a.id);
    moveBy(state, second.id, 1);
    const ordered = visibleAccounts(state).map((a) => a.id);
    expect(ordered[2]).toBe(second.id);
    expect(ordered[1]).toBe(original[2]);
    merge(state, [{ issue: "Primary login offline" }], "claude");
    expect(state.accounts.find((a) => a.id === second.id)!.issue ?? null).toBeNull();
    state.accounts[0].hidden = true;
    expect(visibleAccounts(roundTrip(state)).map((a) => a.id)).toEqual(ordered.slice(1));
  });

  test("dragging to another tile shifts its neighbors and preserves hidden slots", () => {
    const state = initialState();
    const hidden = newAccount("claude", { hidden: true });
    state.accounts.push(hidden);
    const ids = visibleAccounts(state).map((a) => a.id);
    state.accountOrder = [ids[0], hidden.id, ids[1], ids[2], ids[3]];
    expect(moveTo(state, ids[0], ids[3])).toBe(true);
    expect(visibleAccounts(state).map((a) => a.id)).toEqual([ids[1], ids[2], ids[3], ids[0]]);
    expect(state.accountOrder![1]).toBe(hidden.id);
    expect(moveTo(state, hidden.id, ids[0])).toBe(false);
    expect(moveTo(state, ids[1], ids[1])).toBe(false);
    expect(moveTo(state, ids[0], ids[1])).toBe(true);
    expect(visibleAccounts(state).map((a) => a.id)).toEqual(ids);
  });

  test("corner badge honors tier and entered price", () => {
    const pro: Account = newAccount("claude", { customTier: "Pro" });
    expect(badgeAmount(pro)).toBe(20);
    pro.customTier = "Max 20x";
    expect(badgeAmount(pro)).toBe(200);
    expect(badgeAmount(newAccount("codex", { customTier: "Pro 500" }))).toBe(500);
    pro.customPrice = "€19.95/month";
    expect(badgeAmount(pro)).toBe(19.95);
    pro.customPrice = "$20 then $40/mo";
    expect(badgeAmount(pro)).toBeUndefined();
    expect(badgeAmount(newAccount("opencodego"))).toBeUndefined();
  });

  test("remaining allowance uses existing stored percent", () => {
    expect(remainingText({ id: "primary", title: "Weekly", percent: 7 })).toBe("93%");
    expect(remainingText(meter(99.6))).toBe("<1%");
    expect(remainingText(meter(100))).toBe("0%");
    expect(remainingText(meter(0))).toBe("100%");
  });

  test("banked grants expire individually and used resets disappear", () => {
    const row = `{"provider":"codex","usage":{"primary":{"usedPercent":8},"codexResetCredits":{"credits":[{"title":"Later","status":"available","expires_at":"2031-02-01T10:00:00Z"},{"title":"Earlier","status":"available","expires_at":"2031-01-01T10:00:00Z"},{"title":"Redeemed","status":"used","expires_at":"2031-02-06T00:00:00Z"}]}}}`;
    const bank = read(`[${row}]`, "codex")[0].reading!.bankedResets!;
    expect(bankAvailable(bank, -Infinity).lines[0].startsWith("Earlier")).toBe(true);
    expect(bankAvailable(bank, -Infinity).count).toBe(2);
    expect(bankAvailable(bank, parseDate("2031-01-01T10:00:00Z")!).count).toBe(1);
    expect(bankAvailable(bank, Infinity).count).toBe(0);
  });

  test("missing Claude reset inventory has a source-specific explanation", () => {
    for (const source of ["claude", "cli", "oauth", "web"]) {
      const rows = read(`[{"provider":"claude","source":"${source}","usage":{"primary":{"usedPercent":1}}}]`);
      const account = newAccount("claude", { reading: rows[0].reading });
      expect(claudeResetNote(account)).toBeTruthy();
      expect(claudeResetNote(account)!.includes("CLI")).toBe(["cli", "claude"].includes(source));
      expect(account.reading!.bankedResets).toBeNull();
    }
  });

  test("Claude bank summary stays account scoped", () => {
    const data = `[{"provider":"claude","account":"one","usage":{"primary":{"usedPercent":2},"details":[{"rows":[{"label":"Limit Reset Credits","value":"2 available","secondaryValue":"Expires Dec 1 at 08:00"}]}]}},{"provider":"claude","account":"two","usage":{"primary":{"usedPercent":14}}}]`;
    const rows: Observation[] = read(data);
    expect(bankAvailable(rows[0].reading!.bankedResets!, Date.now()).count).toBe(2);
    expect(rows[0].reading!.bankedResets!.expiryNote).toBe("Expires Dec 1 at 08:00");
    expect(rows[1].reading!.bankedResets).toBeNull();
  });

  test("unreadable reports and empty provider lists are errors", () => {
    expect(() => read("not json")).toThrow("unreadable");
    expect(() => read(`[{"provider":"codex"}]`)).toThrow("no accounts");
  });
});
