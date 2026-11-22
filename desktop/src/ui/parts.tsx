import { ComponentChildren } from "preact";
import { useRef, useState } from "preact/hooks";
import { openUrl } from "@tauri-apps/plugin-opener";
import {
  Account, Meter, Provider, Proximity, accountName, bankAvailable, badgeAmount, claudeResetNote, formatDateTime,
  innerMeter, isLow, isStale, meterOf, priceDetail, priceText, remaining, remainingText, resetCountdown, tierName,
} from "../model";
import { Icon, IconName } from "./icons";
import claude from "../logos/claude.png";
import codex from "../logos/codex.png";
import grok from "../logos/grok.png";
import opencodego from "../logos/opencodego.png";

const logos: Record<Provider, string> = { claude, codex, grok, opencodego };

export const open = (url: string) => void openUrl(url).catch(() => undefined);

export function Link({ href, children, class: className }: { href: string; children: ComponentChildren; class?: string }) {
  return (
    <a
      class={`link ${className ?? ""}`}
      href={href}
      onClick={(e) => {
        e.preventDefault();
        open(href);
      }}
    >
      {children}
    </a>
  );
}

export function ProviderLogo({ provider, size }: { provider: Provider; size: number }) {
  return <img src={logos[provider]} width={size} height={size} alt="" draggable={false} style={{ objectFit: "contain" }} />;
}

export function GlyphButton(props: { icon: IconName; help: string; lit?: boolean; filled?: boolean; disabled?: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      class={`glyph${props.lit ? " lit" : ""}`}
      title={props.help}
      aria-label={props.help}
      disabled={props.disabled}
      onClick={props.onClick}
    >
      <Icon name={props.icon} filled={props.filled} />
    </button>
  );
}

const proximityColor: Record<Proximity, string> = {
  unknown: "var(--quiet)",
  due: "var(--quiet)",
  withinHour: "var(--healthy)",
  withinSixHours: "#FFBC26",
  withinDay: "#44ADFF",
  later: "#B680FF",
};

function Arc({ meter, size, lineWidth, stale }: { meter?: Meter; size: number; lineWidth: number; stale: boolean }) {
  const color = meter ? (isLow(meter) ? "var(--low)" : "var(--healthy)") : "var(--quiet)";
  const r = (size - lineWidth) / 2;
  const circumference = 2 * Math.PI * r;
  const fraction = meter ? remaining(meter) / 100 : 0;
  return (
    <svg width={size} height={size} style={{ position: "absolute", inset: 0, margin: "auto", transform: "rotate(-90deg)" }} aria-hidden="true">
      <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke={color} stroke-width={lineWidth} opacity={meter && isLow(meter) ? 0.48 : 0.16} />
      {fraction > 0 && (
        <circle
          cx={size / 2}
          cy={size / 2}
          r={r}
          fill="none"
          stroke={color}
          stroke-width={lineWidth}
          stroke-linecap="round"
          stroke-dasharray={`${circumference * fraction} ${circumference}`}
          opacity={stale ? 0.55 : 1}
        />
      )}
    </svg>
  );
}

function badgeColor(amount: number) {
  return amount >= 500 ? "#B680FF" : amount >= 200 ? "var(--signal)" : amount >= 100 ? "#FFBC26" : "#44ADFF";
}

export function tooltip(account: Account, now: number): string {
  const outer = meterOf(account);
  const inner = innerMeter(account);
  const parts = [accountName(account), tierName(account) ?? "Tier unknown", priceDetail(account)];
  const reading = account.reading;
  if (reading) {
    if (reading.identity) parts.push(reading.identity);
    for (const m of reading.meters) {
      const ring = m.id === outer?.id ? "Outer ring · " : m.id === inner?.id ? "Inner ring · " : "";
      parts.push(`${ring}${m.title} · ${remainingText(m)} left` + (m.reset != null ? ` · resets ${formatDateTime(m.reset)}` : ""));
    }
    const bank = reading.bankedResets ? bankAvailable(reading.bankedResets, now) : undefined;
    if (bank && bank.count > 0) {
      parts.push(`${bank.count} banked ${bank.count === 1 ? "reset" : "resets"}`, ...bank.lines);
    }
    const note = claudeResetNote(account);
    if (note) parts.push(note);
    parts.push((reading.estimated ? "Local estimate · " : "") + "Updated " + formatDateTime(reading.updated));
  }
  if (account.issue) parts.push(account.issue);
  parts.push("Drag to change the account order.");
  return parts.join("\n");
}

/** Reorders by pointer so the drag never touches the OS drag-and-drop system. */
export function useTileDrag(source: string | undefined, click: () => void, drop?: (dragged: string) => boolean) {
  const start = useRef<{ x: number; y: number; id: number } | null>(null);
  const [dragging, setDragging] = useState(false);
  const target = useRef<HTMLElement | null>(null);

  const receiverAt = (x: number, y: number, self: HTMLElement) => {
    const hit = (document.elementFromPoint(x, y) as HTMLElement | null)?.closest<HTMLElement>("[data-drop]");
    return hit && hit !== self ? hit : null;
  };
  const mark = (next: HTMLElement | null) => {
    if (target.current === next) return;
    target.current?.classList.remove("drop-target");
    target.current = next;
    next?.classList.add("drop-target");
  };
  const clear = () => {
    start.current = null;
    mark(null);
    setDragging(false);
  };

  return {
    dragging,
    handlers: {
      "data-drop": "",
      onPointerDown(e: PointerEvent) {
        if (e.button !== 0) return;
        start.current = { x: e.clientX, y: e.clientY, id: e.pointerId };
      },
      onPointerMove(e: PointerEvent) {
        const s = start.current;
        if (!s || !source || e.pointerId !== s.id) return;
        const el = e.currentTarget as HTMLElement;
        if (!dragging) {
          if (Math.hypot(e.clientX - s.x, e.clientY - s.y) < 5) return;
          el.setPointerCapture(e.pointerId);
          setDragging(true);
        }
        mark(receiverAt(e.clientX, e.clientY, el));
      },
      onPointerUp(e: PointerEvent) {
        if (!start.current) return;
        const wasDragging = dragging;
        const receiver = wasDragging ? receiverAt(e.clientX, e.clientY, e.currentTarget as HTMLElement) : null;
        clear();
        if (wasDragging) {
          if (source && receiver) receiver.dispatchEvent(new CustomEvent("tile-drop", { detail: source }));
        } else click();
      },
      onPointerCancel: clear,
      onKeyDown(e: KeyboardEvent) {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          click();
        }
      },
      // Preact binds "ontile-drop" to the custom "tile-drop" event.
      "ontile-drop": (e: CustomEvent<string>) => void drop?.(e.detail),
    },
  };
}

export function RingTile(props: {
  account: Account;
  width: number;
  compact: boolean;
  subtitle: string;
  selected: boolean;
  divider: boolean;
  now: number;
  drop: (dragged: string) => boolean;
  action: () => void;
}) {
  const { account, compact, now } = props;
  const meter = meterOf(account);
  const inner = innerMeter(account);
  const diameter = compact ? 38 : 52;
  const bank = account.reading?.bankedResets ? bankAvailable(account.reading.bankedResets, now) : undefined;
  const stale = isStale(account, now);
  const amount = badgeAmount(account);
  const countdown = resetCountdown(meter?.reset, now);
  const drag = useTileDrag(account.id, props.action, props.drop);
  const price = priceText(account);
  return (
    <div
      class={`tile${compact ? " compact" : ""}${props.selected ? " selected" : ""}${drag.dragging ? " dragging" : ""}`}
      style={{ width: props.width }}
      role="button"
      tabIndex={0}
      title={tooltip(account, now)}
      aria-label={`${accountName(account)}, ${meter ? remainingText(meter) : "unknown"} left, ${props.subtitle}`}
      {...drag.handlers}
    >
      <div class="tile-meta">
        {amount !== undefined && (
          <span class="badge" style={{ color: badgeColor(amount), borderColor: badgeColor(amount) }}>
            {String(amount)}
          </span>
        )}
        <span class="countdown" style={{ color: proximityColor[countdown.proximity] }}>
          <Icon name="clock" size={compact ? 8 : 9} />
          {compact ? countdown.compactText : countdown.text}
        </span>
      </div>
      <div class="ring" style={{ width: diameter, height: diameter }}>
        <Arc meter={meter} size={diameter} lineWidth={compact ? 3 : 4} stale={stale} />
        {inner && (
          <Arc
            meter={inner}
            size={diameter - (compact ? 10 : 14)}
            lineWidth={compact ? 2.5 : 3}
            stale={stale || (inner.reset ?? Infinity) <= now}
          />
        )}
        <ProviderLogo provider={account.provider} size={compact ? 15 : 21} />
        {bank && bank.count > 0 && <span class="bank-dot" />}
      </div>
      {!compact && <div class="tile-name">{accountName(account)}</div>}
      <div class="tile-left">{meter ? `${remainingText(meter)} left` : "—"}</div>
      {!compact && (
        <>
          <div class={`tile-sub${account.issue || stale ? " warn" : ""}`}>{props.subtitle}</div>
          <div class="tile-tier">
            <div class="strong">{tierName(account) ?? "Tier unknown"}</div>
            {price && <div>{price}</div>}
          </div>
        </>
      )}
      {props.divider && <span class="provider-divider" />}
    </div>
  );
}
