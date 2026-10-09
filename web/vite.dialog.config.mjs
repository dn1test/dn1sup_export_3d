import path from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";
import tailwindcss from "@tailwindcss/vite";
import { classicScriptTag } from "./scripts/vite-plugin-classic-html.mjs";

const root = path.dirname(fileURLToPath(import.meta.url));
const outDir = path.resolve(root, "../dn1sup_export_3d/ui");

// Диалог экспорта собирается в папку расширения рядом с export_dialog.rb.
// emptyOutDir выключен: в ui/ лежит Ruby-код, который стирать нельзя.
export default defineConfig({
  base: "./",
  plugins: [vue(), tailwindcss(), classicScriptTag()],
  publicDir: false,
  build: {
    outDir,
    emptyOutDir: false,
    target: "es2017",
    modulePreload: false,
    rollupOptions: {
      input: { dialog: path.resolve(root, "export_dialog.html") },
      output: {
        format: "iife",
        inlineDynamicImports: true,
        entryFileNames: "assets/export_dialog.js",
        chunkFileNames: "assets/[name].js",
        assetFileNames: "assets/[name][extname]",
      },
    },
  },
});
