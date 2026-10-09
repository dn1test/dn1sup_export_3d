import { createApp } from "vue";
import App from "./App.vue";
import "./style.css";

// В single-file сборке инлайн-скрипт в <head> выполняется до появления #app,
// поэтому монтируем после готовности DOM.
const mount = () => createApp(App).mount("#app");
if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", mount, { once: true });
} else {
  mount();
}
