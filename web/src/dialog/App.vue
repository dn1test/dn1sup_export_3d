<script setup>
import { computed, onMounted, reactive, ref } from "vue";
import { callSketchUp } from "../shared/bridge.js";
import { formatBytes } from "../shared/format.js";
import { plural } from "../shared/plural.js";

// Ruby -> JS: state пушится через window.exporter.receiveState (см.
// ExportDialog#push_state), JS -> Ruby: window.sketchup.*.
const state = reactive({
  mode: "idle",
  message: null,
  stats: null,
  web_dir_name: null,
  selection_count: null,
  default_path: null,
  single_file_name: null,
});

const scope = ref("all");
const path = ref("");
const includeHidden = ref(false);
const singleFile = ref(true);

const exporting = computed(() => state.mode === "exporting");
const done = computed(() => state.mode === "done" && state.stats);
const selectionBlocked = computed(() => typeof state.selection_count === "number" && state.selection_count === 0);

const statsLines = computed(() => {
  const s = state.stats;
  if (!s) return [];
  return [
    `${s.faces} ${plural(s.faces, "грань", "грани", "граней")} (${s.triangles.toLocaleString("ru-RU")} ${plural(s.triangles, "треугольник", "треугольника", "треугольников")}), ` +
      `${s.materials} ${plural(s.materials, "материал", "материала", "материалов")}, ` +
      `${s.textures} ${plural(s.textures, "текстура", "текстуры", "текстур")}`,
    `${formatBytes(s.bytes)} за ${s.seconds} с`,
    s.path,
  ];
});

onMounted(() => {
  window.exporter = {
    setOutputPath: (p) => {
      path.value = p;
    },
    receiveState: (s) => {
      Object.assign(state, s);
      if (s.default_path && !path.value) path.value = s.default_path;
    },
  };
  // Сообщаем Ruby, что страница жива: execute_script до загрузки теряется.
  callSketchUp("dialog_ready");
});

function browse() {
  callSketchUp("browse_output", path.value);
}

function doExport() {
  callSketchUp("export_start", JSON.stringify({
    scope: scope.value,
    path: path.value,
    include_hidden: includeHidden.value,
    single_file: singleFile.value,
  }));
}

function cancel() {
  callSketchUp("cancel");
}

function openViewer() {
  callSketchUp("open_viewer");
}

function openFolder() {
  callSketchUp("open_folder");
}
</script>

<template>
  <div class="flex h-full flex-col gap-3 overflow-y-auto p-4">
    <section>
      <h2 class="mb-2 text-[11px] font-semibold uppercase tracking-wide text-zinc-500">Что экспортировать</h2>
      <div class="grid grid-cols-1 gap-2">
        <label
          class="flex cursor-pointer items-start gap-2.5 rounded-lg border bg-white p-2.5 transition-colors"
          :class="scope === 'all' ? 'border-sky-500 ring-1 ring-sky-500' : 'border-zinc-300 hover:border-zinc-400'"
        >
          <input v-model="scope" type="radio" value="all" class="mt-0.5 accent-sky-600" />
          <span>
            <span class="block font-medium text-zinc-800">Вся модель</span>
            <span class="text-xs text-zinc-500">Все объекты модели</span>
          </span>
        </label>

        <label
          class="flex items-start gap-2.5 rounded-lg border bg-white p-2.5 transition-colors"
          :class="[
            scope === 'selection' ? 'border-sky-500 ring-1 ring-sky-500' : 'border-zinc-300',
            selectionBlocked ? 'cursor-not-allowed opacity-50' : 'cursor-pointer hover:border-zinc-400',
          ]"
        >
          <input
            v-model="scope"
            type="radio"
            value="selection"
            class="mt-0.5 accent-sky-600"
            :disabled="selectionBlocked"
          />
          <span>
            <span class="block font-medium text-zinc-800">
              Только выделенное
              <span v-if="typeof state.selection_count === 'number'" class="ml-1 rounded-full bg-zinc-100 px-1.5 py-0.5 text-[10px] text-zinc-500">
                {{ state.selection_count }}
              </span>
            </span>
            <span class="text-xs text-zinc-500">
              {{ selectionBlocked ? "Ничего не выделено в модели" : "Выделенные объекты модели" }}
            </span>
          </span>
        </label>
      </div>
    </section>

    <section>
      <h2 class="mb-2 text-[11px] font-semibold uppercase tracking-wide text-zinc-500">Куда сохранить</h2>
      <div class="flex gap-2">
        <input
          v-model="path"
          type="text"
          spellcheck="false"
          placeholder="C:\путь\к\модели.glb"
          class="min-w-0 flex-1 rounded-md border border-zinc-300 bg-white px-2.5 py-1.5 text-xs text-zinc-800 placeholder-zinc-400 focus:border-sky-500 focus:outline-none focus:ring-1 focus:ring-sky-500"
        />
        <button
          type="button"
          :disabled="exporting"
          class="shrink-0 rounded-md border border-zinc-300 bg-white px-3 py-1.5 text-xs font-medium text-zinc-700 hover:bg-zinc-100 disabled:opacity-50"
          @click="browse"
        >
          Обзор…
        </button>
      </div>

      <div class="mt-2.5 space-y-1.5">
        <label class="flex cursor-pointer items-center gap-2 text-xs text-zinc-700">
          <input v-model="includeHidden" type="checkbox" class="accent-sky-600" />
          Включая скрытую геометрию
        </label>
        <label class="flex cursor-pointer items-start gap-2 text-xs text-zinc-700">
          <input v-model="singleFile" type="checkbox" class="mt-0.5 accent-sky-600" />
          <span>
            Также создать один HTML-файл со встроенной моделью
            <span class="block text-[11px] leading-snug text-zinc-500">
              Удобно отправить заказчику: один файл открывается двойным кликом в браузере
            </span>
          </span>
        </label>
      </div>
    </section>

    <p
      v-if="state.mode === 'error'"
      class="rounded-md border border-red-200 bg-red-50 p-2.5 text-xs leading-snug text-red-700"
    >
      {{ state.message || "Экспорт не выполнен." }}
    </p>
    <p
      v-else-if="exporting"
      class="rounded-md border border-blue-200 bg-blue-50 p-2.5 text-xs leading-snug text-blue-800"
    >
      Экспорт выполняется. На больших моделях SketchUp может не отвечать несколько секунд.
    </p>

    <section
      v-if="done"
      class="rounded-lg border border-emerald-200 bg-emerald-50 p-3"
    >
      <div class="whitespace-pre-line font-mono text-[11px] leading-relaxed text-zinc-700">{{ statsLines.join("\n") }}</div>
      <p v-if="state.single_file_name" class="mt-2 text-[11px] text-emerald-800">
        ✓ Файл для отправки: <span class="font-semibold">{{ state.single_file_name }}</span>
      </p>
      <div class="mt-3 flex gap-2">
        <button
          type="button"
          :disabled="!state.web_dir_name"
          class="rounded-md bg-sky-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-sky-500 disabled:opacity-50"
          @click="openViewer"
        >
          Открыть 3D-просмотр
        </button>
        <button
          type="button"
          :disabled="!state.web_dir_name"
          class="rounded-md border border-zinc-300 bg-white px-3 py-1.5 text-xs font-medium text-zinc-700 hover:bg-zinc-100 disabled:opacity-50"
          @click="openFolder"
        >
          Открыть папку
        </button>
      </div>
    </section>

    <div class="mt-auto flex items-center gap-2 pt-1">
      <span v-if="exporting" class="flex items-center gap-2 text-xs text-zinc-600">
        <span class="inline-block h-3.5 w-3.5 animate-spin rounded-full border-2 border-zinc-300 border-t-sky-600"></span>
        Экспорт…
      </span>
      <span class="flex-1"></span>
      <button
        type="button"
        :disabled="exporting"
        class="rounded-md bg-sky-600 px-5 py-1.5 text-xs font-semibold text-white hover:bg-sky-500 disabled:opacity-50"
        @click="doExport"
      >
        Экспорт
      </button>
      <button
        type="button"
        class="rounded-md border border-zinc-300 bg-white px-4 py-1.5 text-xs font-medium text-zinc-700 hover:bg-zinc-100"
        @click="cancel"
      >
        Закрыть
      </button>
    </div>
  </div>
</template>
