// Vite пишет <script type="module" crossorigin ...> даже для IIFE-бандлов.
// Модульный тег Chrome блокирует на file://, а crossorigin требует CORS -
// оба сценария для нас рабочие (двойной клик по index.html, HtmlDialog).
// Плагин переписывает тег собранного бандла на классический <script src>.
export function classicScriptTag() {
  return {
    name: "classic-script-tag",
    transformIndexHtml(html) {
      return html.replace(
        /<script\s+type="module"\s+crossorigin\s+src="([^"]+)"><\/script>/g,
        '<script src="$1" defer></script>'
      );
    },
  };
}
