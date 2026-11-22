import { useState } from "preact/hooks";
import { Account, Reading, accountLabel, accountName, meterOf, newAccount, providerName, providers, Provider, remaining } from "../model";
import { Store } from "../store";
import { GlyphButton, ProviderLogo, open } from "./parts";

const CLI_DOCS = "https://github.com/steipete/CodexBar/blob/main/docs/cli.md";

/** Value for a datetime-local input in the viewer's time zone. */
function localInput(ms: number) {
  const d = new Date(ms);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export function AccountForm({ store, original, done, close }: { store: Store; original: Account | null; done: (id: string | null) => void; close: () => void }) {
  const meter = original ? meterOf(original) : undefined;
  const [live, setLive] = useState(true);
  const [loginEmail, setLoginEmail] = useState("");
  const [provider, setProvider] = useState<Provider>(original?.provider ?? "claude");
  const [label, setLabel] = useState(original?.label ?? "");
  const [tier, setTier] = useState(original?.customTier ?? "");
  const [price, setPrice] = useState(original?.customPrice ?? "");
  const [percent, setPercent] = useState(meter ? String(remaining(meter)) : "");
  const [period, setPeriod] = useState(meter?.title ?? "Weekly");
  const [hasReset, setHasReset] = useState(meter?.reset != null);
  const [reset, setReset] = useState(localInput(meter?.reset ?? Date.now() + 86_400_000));

  const manual = original ? original.manual : !live;
  const trimmedPercent = percent.trim();
  const parsed = Number(trimmedPercent);
  const validPercent = trimmedPercent !== "" && Number.isFinite(parsed) && parsed >= 0 && parsed <= 100 ? parsed : null;
  const email = loginEmail.trim();
  const periods = ["Session", "Daily", "Weekly", "Monthly"];
  if (!periods.includes(period)) periods.push(period);

  const save = () => {
    const customTier = tier.trim() || null;
    const customPrice = price.trim() || null;
    let reading: Reading | undefined;
    if (manual) {
      if (validPercent === null) return;
      const resetMs = hasReset ? new Date(reset).getTime() : NaN;
      reading = {
        meters: [{ id: "manual", title: period, percent: 100 - validPercent, reset: Number.isNaN(resetMs) ? null : resetMs }],
        updated: Date.now(),
        source: "manual",
        estimated: false,
      };
    }
    if (original) {
      store.update(original.id, (a) => {
        a.label = label.trim();
        a.customTier = customTier;
        a.customPrice = customPrice;
        if (reading) a.reading = reading;
      });
      done(original.id);
    } else {
      const account = newAccount(provider, { label: label.trim(), manual: true, reading, customTier, customPrice });
      store.add(account);
      done(account.id);
    }
  };

  const visible = store.visible;
  const hidden = store.state.accounts.filter((a) => a.hidden);

  return (
    <section class="panel form">
      <div class="panel-head">
        <h2 class="grow">{original ? "Edit account" : "Add an account"}</h2>
        <GlyphButton icon="x" help="Cancel" onClick={close} />
      </div>
      {!original && (
        <div class="segmented" role="tablist">
          <button type="button" role="tab" aria-selected={live} class={live ? "on" : ""} onClick={() => setLive(true)}>Connected accounts</button>
          <button type="button" role="tab" aria-selected={!live} class={!live ? "on" : ""} onClick={() => setLive(false)}>Manual entry</button>
        </div>
      )}
      {!original && live ? (
        <>
          <p class="callout quiet">
            Sign in to Claude here. For Codex, OpenCode Go, or Grok, configure the account in the CodexBar CLI, then refresh and choose Add.
          </p>
          <div class="scroll list">
            {[...visible, ...hidden].map((account) => (
              <div class="row list-row" key={account.id}>
                <ProviderLogo provider={account.provider} size={14} />
                <span class="caption strong">{accountName(account)}</span>
                <span class="caption quiet ellipsis grow">{accountLabel(account) ?? (account.manual ? "Manual" : "Default account")}</span>
                {!account.hidden && (
                  <>
                    <GlyphButton icon="up" help={`Move ${accountName(account)} earlier`} disabled={visible[0]?.id === account.id} onClick={() => store.moveBy(account.id, -1)} />
                    <GlyphButton icon="down" help={`Move ${accountName(account)} later`} disabled={visible.at(-1)?.id === account.id} onClick={() => store.moveBy(account.id, 1)} />
                  </>
                )}
                <button
                  type="button"
                  class="link caption"
                  onClick={() => {
                    if (account.hidden) store.showAccount(account.id);
                    done(account.id);
                  }}
                >
                  {account.hidden ? "Add" : "View"}
                </button>
              </div>
            ))}
          </div>
          <form
            class="row"
            onSubmit={(e) => {
              e.preventDefault();
              if (email.includes("@") && !email.includes(" ")) done(store.addClaudeProfile(email));
            }}
          >
            <input class="grow" type="email" placeholder="Claude account email" value={loginEmail} onInput={(e) => setLoginEmail(e.currentTarget.value)} />
            <button type="submit" class="bordered" disabled={!loginEmail.includes("@") || loginEmail.includes(" ")}>Add Claude login</button>
          </form>
          <div class="row">
            <button
              type="button"
              class="bordered"
              onClick={() => (store.needsCodexBar ? store.requestSetup("codexbar") : open(CLI_DOCS))}
            >
              {store.needsCodexBar ? "Set up CodexBar" : "CodexBar account setup ↗"}
            </button>
            <span class="grow" />
            <button type="button" class="bordered" disabled={store.refreshing.size > 0} onClick={() => void store.userRefresh()}>Refresh accounts</button>
          </div>
        </>
      ) : (
        <>
          <div class="scroll">
            <div class="grid">
              <label>Provider</label>
              {original ? (
                <span>{providerName[provider]}</span>
              ) : (
                <select value={provider} onChange={(e) => setProvider(e.currentTarget.value as Provider)}>
                  {providers.map((p) => <option value={p} key={p}>{providerName[p]}</option>)}
                </select>
              )}
              <label for="f-label">Label</label>
              <input id="f-label" placeholder="e.g. Personal, Studio" value={label} onInput={(e) => setLabel(e.currentTarget.value)} />
              <label for="f-tier">Plan tier</label>
              <input id="f-tier" placeholder={original?.reading?.plan ?? "e.g. Go Plus"} value={tier} onInput={(e) => setTier(e.currentTarget.value)} />
              <label for="f-price">Your price</label>
              <input id="f-price" placeholder="e.g. $20/mo or €180/year" value={price} onInput={(e) => setPrice(e.currentTarget.value)} />
              {manual && (
                <>
                  <label for="f-window">Window</label>
                  <select id="f-window" value={period} onChange={(e) => setPeriod(e.currentTarget.value)}>
                    {periods.map((p) => <option value={p} key={p}>{p}</option>)}
                  </select>
                  <label for="f-left">Remaining</label>
                  <span class="row">
                    <input id="f-left" class="narrow" placeholder="0–100" inputMode="decimal" value={percent} onInput={(e) => setPercent(e.currentTarget.value)} /> %
                  </span>
                  <label for="f-reset">Reset</label>
                  <span class="row">
                    <input type="checkbox" aria-label="Set reset" checked={hasReset} onChange={(e) => setHasReset(e.currentTarget.checked)} />
                    {hasReset && <input id="f-reset" type="datetime-local" value={reset} onInput={(e) => setReset(e.currentTarget.value)} />}
                  </span>
                </>
              )}
            </div>
          </div>
          <div class="row">
            {original && (
              <button
                type="button"
                class="link"
                onClick={() => {
                  store.update(original.id, (a) => (a.hidden = true));
                  done(null);
                }}
              >
                Hide account
              </button>
            )}
            <span class="grow" />
            <button type="button" class="bordered" onClick={close}>Cancel</button>
            <button type="button" class="prominent" disabled={manual && validPercent === null} onClick={save}>Save</button>
          </div>
        </>
      )}
    </section>
  );
}
