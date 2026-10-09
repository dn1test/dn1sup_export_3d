// JS -> Ruby: HtmlDialog внедряет глобальный объект `sketchup`, свойства
// которого - зарегистрированные action-callbacks. В обычном браузере его нет:
// вызовы просто игнорируются, viewer остаётся полностью рабочим.
export function callSketchUp(callback, ...args) {
  const bridge = typeof window === "undefined" ? undefined : window.sketchup;
  if (!bridge || typeof bridge[callback] !== "function") return false;
  bridge[callback].apply(bridge, args);
  return true;
}

export function inSketchUp() {
  return typeof window !== "undefined" && !!window.sketchup;
}
