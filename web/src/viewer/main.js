import { createApp } from "vue";
import App from "./App.vue";
import { installCefEventBridge } from "../shared/cef_event_bridge.js";
import "./style.css";

// Перехват addEventListener должен встать ДО монтирования Vue - тогда
// регистрации инвокеров блокируются с самого начала. Без этого дерево
// объектов и панели, появляющиеся после загрузки модели, в HtmlDialog
// SketchUp 2026 получают мёртвые клики (см. cef_event_bridge.js).
installCefEventBridge();

// В single-file сборке инлайн-скрипт в <head> выполняется до появления #app,
// поэтому монтируем после готовности DOM.
const start = () => createApp(App).mount("#app");

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", start, { once: true });
} else {
  start();
}
