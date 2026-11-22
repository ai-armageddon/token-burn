import {
  Account, accountName, bankAvailable, claudeResetNote, dashboard, formatDateTime, innerMeter, listPlan,
  meterOf, priceDetail, providerName, remainingText, tierName,
} from "../model";
import { Store } from "../store";
import { Icon } from "./icons";
import { GlyphButton, Link, ProviderLogo } from "./parts";

export function Detail({ store, account, now, edit, close }: { store: Store; account: Account; now: number; edit: () => void; close: () => void }) {
  const outer = meterOf(account);
  const inner = innerMeter(account);
  const plan = listPlan(account);
  const busy = store.refreshingProfiles.has(account.id);
  const bank = account.reading?.bankedResets ? bankAvailable(account.reading.bankedResets, now) : undefined;
  const note = claudeResetNote(account);
  const reading = account.reading;
  const identity = [account.label ? providerName[account.provider] : null, reading?.identity ?? account.claudeProfileEmail]
    .filter(Boolean)
    .join(" · ");
  return (
    <section class="panel">
      <div class="panel-head">
        <ProviderLogo provider={account.provider} size={23} />
        <div class="grow">
          <h2>{accountName(account)}</h2>
          <div class="caption quiet ellipsis">{identity}</div>
        </div>
        <GlyphButton icon="pencil" help="Edit account" onClick={edit} />
        <GlyphButton icon="x" help="Close details" onClick={close} />
      </div>
      <div class="scroll">
        <div class="row tier-row">
          <div class="grow">
            <div class="strong">{tierName(account) ?? "Tier unknown"}</div>
            <div class="caption quiet">{priceDetail(account)}</div>
          </div>
          {account.customPrice == null && plan && <Link href={plan.source} class="caption">Pricing ↗</Link>}
        </div>
        {account.issue && <p class="caption warn selectable">{account.issue}</p>}
        {account.claudeProfileEmail && (!reading || account.issue) && (
          <button type="button" class="bordered" disabled={busy} onClick={() => void store.refreshProfile(account, true)}>
            {busy ? "Checking Claude login…" : "Sign in to Claude"}
          </button>
        )}
        {bank && bank.count > 0 && (
          <div class="bank">
            <div class="row">
              <span class="bank-dot inline" />
              <span class="strong small">{`${bank.count} banked ${bank.count === 1 ? "reset" : "resets"}`}</span>
            </div>
            {bank.lines.map((line, i) => (
              <div class="caption quiet" key={i}>{line}</div>
            ))}
          </div>
        )}
        {note && (
          <div class="caption quiet row">
            <Icon name="reset" size={11} /> {note}
          </div>
        )}
        {(reading?.meters ?? []).map((meter) => (
          <button
            type="button"
            class="meter-row"
            key={meter.id}
            title={`Show ${meter.title.toLowerCase()} on the ring`}
            onClick={() => store.update(account.id, (a) => (a.preferred = meter.id))}
          >
            <span class={`radio${outer?.id === meter.id ? " on" : ""}`} />
            <span class="grow">
              <span class="row">
                <span class="strong small">{meter.title}</span>
                {(outer?.id === meter.id || inner?.id === meter.id) && (
                  <span class="tiny quiet">{outer?.id === meter.id ? "Outer ring" : "Inner ring"}</span>
                )}
              </span>
              {meter.reset != null && (
                <span class="tiny quiet block">
                  {meter.reset <= now ? `Reset time passed · ${formatDateTime(meter.reset)}` : `Resets ${formatDateTime(meter.reset)}`}
                </span>
              )}
            </span>
            <span class="mono">{remainingText(meter)} left</span>
          </button>
        ))}
      </div>
      <div class="row panel-foot">
        {reading && (
          <span class="tiny quiet">
            {(account.manual ? "Manual entry" : reading.estimated ? "Local estimate" : reading.source.toUpperCase()) + " · " + formatDateTime(reading.updated)}
          </span>
        )}
        <span class="grow" />
        <Link href={dashboard[account.provider]} class="caption">
          Usage page <Icon name="external" size={10} />
        </Link>
      </div>
    </section>
  );
}
