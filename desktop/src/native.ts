import { invoke } from "@tauri-apps/api/core";

export type Tool = "codexbar" | "claude";

export interface RunOutput {
  code: number | null;
  stdout: string;
  timedOut: boolean;
}

export interface PlatformInfo {
  os: string;
  /** "native" runs the CLIs directly; "wsl" runs them in the default WSL distribution. */
  runtime: "native" | "wsl";
  runtimeAvailable: boolean;
  canInstall: boolean;
}

/** Everything the store needs from the host, so tests can supply a fake. */
export interface Runtime {
  platform(): Promise<PlatformInfo>;
  findTool(name: Tool): Promise<string | null>;
  runTool(name: Tool, args: string[], env: Record<string, string>, timeoutSecs: number): Promise<RunOutput>;
  prepareProfile(id: string): Promise<Record<string, string>>;
  installCodexBar(): Promise<void>;
  statePath(): Promise<string>;
  loadState(): Promise<string | null>;
  saveState(contents: string): Promise<void>;
  getPref(key: string): string | null;
  setPref(key: string, value: string | null): void;
}

export function errorMessage(error: unknown): string {
  if (typeof error === "string") return error;
  if (error instanceof Error) return error.message;
  return "Something went wrong.";
}

export const tauriRuntime: Runtime = {
  platform: () => invoke("platform_info"),
  findTool: (name) => invoke("find_tool", { name }),
  runTool: (name, args, env, timeoutSecs) => invoke("run_tool", { name, args, env, timeoutSecs }),
  prepareProfile: (id) => invoke("prepare_profile", { id }),
  installCodexBar: () => invoke("install_codexbar"),
  statePath: () => invoke("state_path"),
  loadState: () => invoke("load_state"),
  saveState: (contents) => invoke("save_state", { contents }),
  getPref(key) {
    try {
      return localStorage.getItem(key);
    } catch {
      return null;
    }
  },
  setPref(key, value) {
    try {
      if (value === null) localStorage.removeItem(key);
      else localStorage.setItem(key, value);
    } catch {
      // Preferences are conveniences; ignore unavailable storage.
    }
  },
};
