// Port of Widget.swift: the Deck, its top bar and page switching.
import { useEffect, useLayoutEffect, useState } from "preact/hooks";
import { Account, accountLabel, isDesktopClaude, isStale, meterOf, providerName } from "../model";
import { Store } from "../store";
import { DeckWindow } from "../window";
import { AccountForm } from "./AccountForm";
import { Detail } from "./Detail";
import { Icon } from "./icons";
import { GlyphButton, RingTile, useTileDrag } from "./parts";
import { DependencySetup } from "./Setup";
import { TokenBurnMark } from "./Mark";

type Page = { kind: "deck" } | { kind: "detail"; id: string } | { kind: "edit"; id: string } | { kind: "add" };
const COMPACT_KEY = "TokenBurnCompactMode";

export function useStore(store: Store) {
  const [, setVersion] = useState(0);
  useLayoutEffect(() => {
    const unsubscribe = store.subscribe(() => setVersion((v) => v + 1));
    // Catch changes made between the first render and this subscription.
    setVersion((v) => v + 1);
    return unsubscribe;
  }, [store]);
}

/** Re-render once a minute so countdowns and expiries stay current. */
function useMinuteClock() {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 30_000);
    return () => clearInterval(id);
  }, []);
  return now;
}

export function App({ store, deck }: { store: Store; deck: DeckWindow }) {
  useStore(store);
  const now = useMinuteClock();
  const [page, setPage] = useState<Page>({ kind: "deck" });
  const [group, setGroup] = useState(0);
  const [prefersCompact, setPrefersCompact] = useState(() => deck.getPref(COMPACT_KEY) === "1");
  const visible = store.visible;
  const compact = prefersCompact && page.kind === "deck" && store.setupTool === null;
  const groupCount = Math.max(1, Math.ceil(visible.length / 5));
  const height = store.setupTool
    ? 276
    : page.kind === "deck"
      ? compact
        ? groupCount > 1 ? 140 : 120
        : 241
      : page.kind === "detail"
        ? 505
        : 535;
  const width = compact ? 298 : 428;

  useEffect(() => void deck.setLayout(width, height), [width, height]);
  useEffect(() => void deck.setPinned(store.state.pinned), [store.state.pinned]);
  useEffect(() => setGroup((g) => Math.min(g, groupCount - 1)), [groupCount]);
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== "Escape") return;
      if (store.setupTool) store.dismissSetup();
      setPage({ kind: "deck" });
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [store]);

  const toggleCompact = () => {
    deck.setPref(COMPACT_KEY, compact ? null : "1");
    setPrefersCompact(!compact);
    setPage({ kind: "deck" });
  };

  const navigate = (id: string | null) => {
    const index = id ? store.visible.findIndex((a) => a.id === id) : -1;
    if (id && index >= 0) {
      setGroup(Math.floor(index / 5));
      setPage({ kind: "detail", id });
    } else setPage({ kind: "deck" });
  };

  const dropOnPageArrow = (id: string, step: number) => {
    const next = group + step;
    if (next < 0 || next >= groupCount) return false;
    const index = step > 0 ? next * 5 : next * 5 + 4;
    const target = store.visible[index];
    if (!target || !store.move(id, target.id)) return false;
    setGroup(next);
    return true;
  };

  const subtitle = (account: Account, duplicates: boolean) => {
    if (isStale(account, now)) return "Last reading";
    if (!account.manual && store.needsCodexBar) return "Setup needed";
    const meter = meterOf(account);
    if (!meter) return isDesktopClaude(account) ? "Connect" : account.issue == null ? "Connecting…" : "Check login";
    const qualifier = account.manual ? "Manual" : account.reading?.estimated ? "Est." : "";
    let text: string;
    const identity = accountLabel(account);
    if (account.label) text = providerName[account.provider];
    else if (duplicates && isDesktopClaude(account)) text = "Desktop";
    else if (duplicates && identity) text = identity.split("@")[0] || identity;
    else text = meter.title === "5-hour" ? "5h" : meter.title;
    return qualifier ? `${qualifier} ${text}` : text;
  };

  const shown = visible.slice(Math.min(group, groupCount - 1) * 5, Math.min(group, groupCount - 1) * 5 + 5);
  const selected = page.kind === "detail" ? page.id : null;
  const pageAccount = page.kind === "detail" || page.kind === "edit" ? store.state.accounts.find((a) => a.id === page.id) : undefined;

  return (
    <div class={`deck${compact ? " compact" : ""}`} style={{ width, height }}>
      <header class="topbar">
        <div class="title" data-tauri-drag-region title="Drag to move Token Burn">
          <span class="grip-dots" data-tauri-drag-region aria-hidden="true" />
          <TokenBurnMark size={compact ? 16 : 22} />
          {!compact && <span class="wordmark" data-tauri-drag-region>TOKEN BURN</span>}
          {!compact && <span class="divider" data-tauri-drag-region />}
          <span class="section" data-tauri-drag-region>{store.setupTool ? "Setup" : "Deck"}</span>
        </div>
        <GlyphButton icon="minus" help="Minimize Token Burn" onClick={() => void deck.minimize()} />
        <GlyphButton
          icon={compact ? "expand" : "compress"}
          help={compact ? "Expand widget" : "Make widget compact"}
          disabled={store.setupTool !== null}
          onClick={toggleCompact}
        />
        <GlyphButton
          icon="pin"
          filled={store.state.pinned}
          lit={store.state.pinned}
          help={store.state.pinned ? "Unpin window" : "Keep above other windows"}
          onClick={() => store.setPinned(!store.state.pinned)}
        />
        <GlyphButton
          icon="refresh"
          help={store.needsCodexBar ? "Set up live tracking" : "Refresh all accounts"}
          disabled={store.refreshing.size > 0}
          onClick={() => void store.userRefresh()}
        />
        <GlyphButton
          icon="plus"
          help="Add or restore an account"
          lit={page.kind === "add"}
          onClick={() => {
            if (store.setupTool) store.dismissSetup();
            setPage(page.kind === "add" ? { kind: "deck" } : { kind: "add" });
          }}
        />
      </header>
      {store.storageIssue && <div class="storage-issue">{store.storageIssue}</div>}
      {store.setupTool ? (
        <DependencySetup store={store} tool={store.setupTool} />
      ) : (
        <>
          <div class="tiles">
            {shown.map((account, index) => {
              const duplicates = visible.filter((a) => a.provider === account.provider).length > 1;
              return (
                <RingTile
                  key={account.id}
                  account={account}
                  width={compact ? 54 : visible.length >= 5 ? 76 : 95}
                  compact={compact}
                  subtitle={subtitle(account, duplicates)}
                  selected={selected === account.id}
                  divider={index + 1 < shown.length && shown[index + 1].provider !== account.provider}
                  now={now}
                  drop={(dragged) => store.move(dragged, account.id)}
                  action={() => setPage(selected === account.id ? { kind: "deck" } : { kind: "detail", id: account.id })}
                />
              );
            })}
            {visible.length === 0 && (
              <button type="button" class="bordered" onClick={() => setPage({ kind: "add" })}>
                Add an account
              </button>
            )}
          </div>
          {(!compact || groupCount > 1) && (
            <footer class="status">
              <span class={`dot${store.refreshing.size > 0 ? " busy" : ""}`} />
              <span>{store.refreshing.size > 0 ? "Refreshing…" : `${visible.length} ${visible.length === 1 ? "account" : "accounts"}`}</span>
              <span class="spacer" />
              <span class="auto">AUTO 5 MIN</span>
              {groupCount > 1 && (
                <>
                  <PageArrow dir="left" disabled={group === 0} onClick={() => setGroup(group - 1)} drop={(id) => dropOnPageArrow(id, -1)} />
                  <span>{group + 1} / {groupCount}</span>
                  <PageArrow dir="right" disabled={group + 1 >= groupCount} onClick={() => setGroup(group + 1)} drop={(id) => dropOnPageArrow(id, 1)} />
                </>
              )}
            </footer>
          )}
          {page.kind !== "deck" && <hr />}
          {page.kind === "detail" && pageAccount && (
            <Detail
              store={store}
              account={pageAccount}
              now={now}
              edit={() => setPage({ kind: "edit", id: pageAccount.id })}
              close={() => setPage({ kind: "deck" })}
            />
          )}
          {page.kind === "edit" && pageAccount && (
            <AccountForm
              key={pageAccount.id}
              store={store}
              original={pageAccount}
              done={navigate}
              close={() => setPage({ kind: "detail", id: pageAccount.id })}
            />
          )}
          {page.kind === "add" && <AccountForm store={store} original={null} done={navigate} close={() => setPage({ kind: "deck" })} />}
        </>
      )}
    </div>
  );
}

function PageArrow(props: { dir: "left" | "right"; disabled: boolean; onClick: () => void; drop: (id: string) => boolean }) {
  const help = props.dir === "left" ? "Previous accounts" : "Next accounts";
  const drag = useTileDrag(undefined, () => !props.disabled && props.onClick(), props.drop);
  const handlers = props.disabled ? {} : drag.handlers;
  return (
    <span class={`page-arrow${props.disabled ? " disabled" : ""}`} role="button" tabIndex={props.disabled ? -1 : 0} title={help} aria-label={help} {...handlers}>
      <Icon name={props.dir} size={10} />
    </span>
  );
}
