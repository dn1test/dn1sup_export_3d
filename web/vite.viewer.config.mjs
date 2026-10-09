import path from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";
import tailwindcss from "@tailwindcss/vite";
import { classicScriptTag } from "./scripts/vite-plugin-classic-html.mjs";

const root = path.dirname(fileURLToPath(import.meta.url));
const outDir = path.resolve(root, "../dn1sup_export_3d/viewer");

// Собранный viewer попадает прямо в папку расширения: index.html + assets/.
// Формат IIFE одним куском даёт обычный <script>: он работает и в HtmlDialog,
// и по двойному клику на file://, где Chrome блокирует ES-модули.
export default defineConfig({
  base: "./",
  plugins: [vue(), tailwindcss(), classicScriptTag()],
  publicDir: false,
  build: {
    outDir,
    emptyOutDir: true,
    target: "es2017",
    modulePreload: false,
    rollupOptions: {
      input: { index: path.resolve(root, "index.html") },
      output: {
        format: "iife",
        inlineDynamicImports: true,
        entryFileNames: "assets/viewer.js",
        chunkFileNames: "assets/[name].js",
        assetFileNames: "assets/[name][extname]",
      },
    },
  },
});
