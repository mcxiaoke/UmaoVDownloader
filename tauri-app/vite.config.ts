import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

export default defineConfig({
  plugins: [react()],
  clearScreen: false,
  server: {
    port: 1420,
    strictPort: true,
    proxy: {
      "/parse": {
        target: "http://localhost:3333",
        changeOrigin: true,
      },
      "/download": {
        target: "http://localhost:3333",
        changeOrigin: true,
      },
      "/zip": {
        target: "http://localhost:3333",
        changeOrigin: true,
      },
      "/api": {
        target: "http://localhost:3333",
        changeOrigin: true,
      },
    },
  },
  envPrefix: ["VITE_", "TAURI_"],
  build: {
    target: ["es2021", "chrome100", "safari13"],
    minify: !process.env.TAURI_DEBUG ? "esbuild" : false,
    sourcemap: !!process.env.TAURI_DEBUG,
  },
});
