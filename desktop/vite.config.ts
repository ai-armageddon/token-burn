import { defineConfig } from "vite";

// Tauri serves the built files; the dev server port must match tauri.conf.json.
export default defineConfig({
  clearScreen: false,
  esbuild: { jsx: "automatic", jsxImportSource: "preact" },
  server: { port: 1420, strictPort: true },
  build: { target: ["chrome110", "safari16"], outDir: "dist", emptyOutDir: true },
  test: { environment: "node" },
} as any);
