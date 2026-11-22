import { render } from "preact";
import { listen } from "@tauri-apps/api/event";
import { tauriRuntime } from "./native";
import { Store } from "./store";
import { App } from "./ui/App";
import { DeckWindow } from "./window";
import "./styles.css";

async function main() {
  if (import.meta.env.DEV && !("__TAURI_INTERNALS__" in window && "invoke" in (window as any).__TAURI_INTERNALS__)) {
    await import("./preview");
  }
  const zoom = document.getElementById("zoom")!;
  const grip = document.getElementById("grip")!;
  const store = new Store(tauriRuntime);
  const deck = new DeckWindow(zoom, grip, tauriRuntime);
  await store.load();
  render(<App store={store} deck={deck} />, zoom);
  await listen("tray-toggle-pin", () => store.setPinned(!store.state.pinned));
  await listen("tray-refresh", () => void store.userRefresh());
  await store.start();
}

void main();
