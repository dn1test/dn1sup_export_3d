import { createApp } from "vue";
import App from "./App.vue";
import "./style.css";

// В single-file сборке инлайн-скрипт в <head> выполняется до появления #app,
// поэтому монтируем после готовности DOM.
const mount = () => createApp(App).mount("#app");

// SketchUp 2026 (CEF): обработчики, которые Vue вешает на элементы при
// монтировании, могут не срабатывать — клик доходит до самого элемента
// (слушатели, добавленные позже, исправно вызываются), но инвокер Vue не
// запускается. Лечение: повторно регистрируем инвокеры из реестра Vue
// (Symbol(_vei) в runtime-dom). Это безопасно: addEventListener игнорирует
// дубликаты «тип + та же функция», поэтому в здоровом окружении повторная
// регистрация — no-op, а модификаторы Vue уже зашиты внутрь инвокера.
// Панель результата и прогресса появляются после монтирования, поэтому чиним
// и новые элементы через MutationObserver.
const VEI_DESCRIPTION = "_vei";

function repairVueListeners(root) {
  if (!root) return;
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT);
  let current = walker.currentNode;
  while (current) {
    const symbol = Object.getOwnPropertySymbols(current).find(
      (s) => s.description === VEI_DESCRIPTION
    );
    if (symbol) {
      for (const [rawName, invoker] of Object.entries(current[symbol])) {
        current.addEventListener(rawName.slice(2).toLowerCase(), invoker);
      }
    }
    current = walker.nextNode();
  }
}

let observer = null;

const start = () => {
  mount();
  const appRoot = document.getElementById("app");
  if (appRoot && typeof MutationObserver !== "undefined") {
    observer = new MutationObserver(() => repairVueListeners(appRoot));
    observer.observe(appRoot, { childList: true, subtree: true });
  }
  repairVueListeners(appRoot);
};

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", start, { once: true });
} else {
  start();
}
