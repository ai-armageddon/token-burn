import { invoke } from "@tauri-apps/api/core";
import { LogicalSize, currentMonitor, getCurrentWindow } from "@tauri-apps/api/window";
import { Runtime } from "./native";

const SCALE_KEY = "TokenBurnWindowScale";
const clamp = (value: number) => Math.min(2, Math.max(0.65, value));

/**
 * Sizes the borderless Deck window. The page lays out in logical points and the
 * browser scales it with CSS zoom, so hit testing always matches what is drawn.
 */
export class DeckWindow {
  private win = getCurrentWindow();
  private layout = { w: 428, h: 241 };
  private scale: number;
  private applied = 1;
  private busy = false;
  private again = false;

  constructor(private zoom: HTMLElement, grip: HTMLElement, private rt: Runtime) {
    const saved = Number(rt.getPref(SCALE_KEY));
    this.scale = Number.isFinite(saved) && saved > 0 ? clamp(saved) : 1;
    this.attachGrip(grip);
  }

  getPref = (key: string) => this.rt.getPref(key);
  setPref = (key: string, value: string | null) => this.rt.setPref(key, value);

  async setLayout(w: number, h: number) {
    this.layout = { w, h };
    await this.apply();
  }

  minimize = () => this.win.minimize();

  async setPinned(pinned: boolean) {
    await this.win.setAlwaysOnTop(pinned).catch(() => undefined);
    await invoke("sync_pinned", { pinned }).catch(() => undefined);
  }

  /** Coalesces rapid grip moves into one native resize at a time. */
  private async apply() {
    if (this.busy) {
      this.again = true;
      return;
    }
    this.busy = true;
    try {
      do {
        this.again = false;
        const { w, h } = this.layout;
        let s = this.scale;
        const monitor = await currentMonitor().catch(() => null);
        if (monitor) {
          const factor = monitor.scaleFactor || 1;
          s = Math.min(s, monitor.size.width / factor / w, monitor.size.height / factor / h);
        }
        this.applied = s;
        this.zoom.style.zoom = String(s);
        await this.win.setSize(new LogicalSize(Math.round(w * s), Math.round(h * s))).catch(() => undefined);
      } while (this.again);
    } finally {
      this.busy = false;
    }
  }

  /**
   * The window's top-left corner stays put while resizing, so the pointer's
   * position inside the window gives the new size. That avoids screen
   * coordinates, which Wayland does not report.
   */
  private attachGrip(grip: HTMLElement) {
    let offset: { x: number; y: number } | null = null;
    const update = (e: PointerEvent, finished: boolean) => {
      if (!offset) return;
      const { w, h } = this.layout;
      const x = e.clientX + offset.x;
      const y = e.clientY + offset.y;
      this.scale = clamp((x * w + y * h) / (w * w + h * h));
      void this.apply();
      if (finished) this.rt.setPref(SCALE_KEY, String(this.scale));
    };
    grip.addEventListener("pointerdown", (e) => {
      if (e.button !== 0) return;
      e.preventDefault();
      grip.setPointerCapture(e.pointerId);
      offset = { x: this.layout.w * this.applied - e.clientX, y: this.layout.h * this.applied - e.clientY };
    });
    grip.addEventListener("pointermove", (e) => update(e, false));
    grip.addEventListener("pointerup", (e) => {
      update(e, true);
      offset = null;
    });
    grip.addEventListener("pointercancel", () => (offset = null));
  }
}
