import { createApp } from "vue";
import App from "./App.vue";
import "./style.css";

// В single-file сборке инлайн-скрипт в <head> выполняется до появления #app,
// поэтому монтируем после готовности DOM.
const mount = () => createApp(App).mount("#app");

// SketchUp 2026 (CEF) теряет часть DOM-слушателей. Установлено вживую на
// диалоге экспорта: инвокер Vue лежит в реестре (Symbol(_vei)), dispatch
// до элемента доходит, свежий слушатель на той же кнопке срабатывает, но
// собственная регистрация Vue не вызывается; повторный addEventListener той
// же функции - no-op (дедупликация «тип + функция»), а слушатели,
// навешанные вне контекста первичной загрузки страницы, умирают даже при
// перерегистрации новыми функциями. Стабильно получают реальные клики
// только слушатели, навешанные один раз при загрузке (кнопки каркаса
// работают, динамическая панель результата - нет).
//
// Поэтому слушатели Vue не регистрируются в DOM вовсе: addEventListener
// перехвачен на прототипе, и регистрации инвокеров Vue (у них есть
// свойство .value - createInvoker в runtime-dom) просто пропускаются.
// Свои слушатели страницы (Three.js, камера) признака не имеют и
// регистрируются как обычно. Доставку выполняет ОДИН делегированный
// слушатель на документ, навешанный при загрузке: он находит ближайший
// инвокер в _vei от цели события и вызывает его напрямую - без DOM-dispatch,
// поэтому «протухание» регистраций ему не страшно, а реестр читается в
// момент события, так что патчи Vue подхватываются автоматически.
const DELEGATED_TYPES = ["click", "input", "change"];
const VEI_DESCRIPTION = "_vei";

const nativeAddEventListener = EventTarget.prototype.addEventListener;

EventTarget.prototype.addEventListener = function (type, listener, options) {
  if (listener && typeof listener.value === "function") return; // инвокер Vue
  return nativeAddEventListener.call(this, type, listener, options);
};

function veiOf(el) {
  const symbol = Object.getOwnPropertySymbols(el).find(
    (s) => s.description === VEI_DESCRIPTION
  );
  return symbol ? el[symbol] : null;
}

// Воспроизводит нативную всплывающую диспетчеризацию для одного типа
// события: от цели вверх до ближайших элементов с инвокером. Вызов инвокера
// отложен в обычную задачу (setTimeout 0): из стека dispatch события вызовы
// моста window.sketchup.* в CEF могут теряться, а из обычной задачи -
// доходят (проверено вживую). Обработчики диалога не используют
// stopPropagation/preventDefault, поэтому асинхронность для них безопасна.
function dispatchThroughVue(event) {
  const key = "on" + event.type[0].toUpperCase() + event.type.slice(1);
  const calls = [];
  for (let el = event.target; el && el.getAttribute; el = el.parentElement) {
    const invokers = veiOf(el);
    const invoker = invokers && invokers[key];
    if (typeof invoker === "function") calls.push([invoker, el]);
  }
  for (const [invoker, el] of calls) {
    setTimeout(() => invoker.call(el, event), 0);
  }
}

// Страховка: если CEF «протухит» и делегированные слушатели, раз в секунду
// они перерегистрируются новой функцией (старая снимается - обработчик
// всегда ровно один, двойного срабатывания нет и в здоровом браузере).
let delegatedHandler = null;

function attachDelegated() {
  if (delegatedHandler) {
    for (const type of DELEGATED_TYPES) {
      document.removeEventListener(type, delegatedHandler, true);
    }
  }
  delegatedHandler = (event) => dispatchThroughVue(event);
  for (const type of DELEGATED_TYPES) {
    nativeAddEventListener.call(document, type, delegatedHandler, true);
  }
}

const start = () => {
  mount();
  attachDelegated();
  setInterval(attachDelegated, 1000);
};

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", start, { once: true });
} else {
  start();
}
