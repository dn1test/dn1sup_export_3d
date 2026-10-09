<script setup>
import { onBeforeUnmount, onMounted, ref } from "vue";
import ViewerEngine from "../../viewer/engine/ViewerEngine.js";
import Icon from "../../viewer/components/Icon.vue";
import { formatBytes } from "../../shared/format.js";
import { plural } from "../../shared/plural.js";

// Левая панель диалога: канвас с ViewerEngine (тот же движок, что и у
// большого просмотрщика) + тулбар + оверлей состояния построения предпросмотра.
// Модель приходит из Ruby готовым data:-URI (см. ExportDialog#complete_preview).
const props = defineProps({
  status: { type: String, default: "empty" }, // empty|building|assembling|ready|error|too_large|empty_selection
  pct: { type: Number, default: 0 },
  current: { type: String, default: null },
  message: { type: String, default: null },
  bytes: { type: Number, default: null },
  objects: { type: Number, default: null },
  triangles: { type: Number, default: null },
  textures: { type: Boolean, default: false },
  canRefresh: { type: Boolean, default: true },
  offline: { type: Boolean, default: false },
});

const emit = defineEmits(["select", "stats", "error", "refresh", "toggle-textures"]);

const container = ref(null);
const canvas = ref(null);
const wireframe = ref(false);
const edges = ref(true);

let engine = null;
let resizeObserver = null;

onMounted(() => {
  engine = new ViewerEngine(canvas.value);
  engine.resize();
  resizeObserver = new ResizeObserver(() => engine.resize());
  resizeObserver.observe(container.value);
  engine.on("viewerReady", (detail) => emit("stats", { objects: detail.objects, triangles: detail.triangles }));
  engine.on("loadError", (detail) => emit("error", detail.error));
  engine.on("objectSelected", (detail) => {
    // Ruby отправляем всю цепочку (деталь -> инстанс): он выберет первую
    // существующую сущность, как и в большом просмотрщике.
    const chain = detail.chain && detail.chain.length ? detail.chain : [detail.pid];
    emit("select", chain);
  });
});

onBeforeUnmount(() => {
  if (resizeObserver) resizeObserver.disconnect();
  if (engine) engine.dispose();
  engine = null;
});

defineExpose({
  load: (url) => engine && engine.loadModel(url),
  setSelection: (pids) => engine && engine.setSelection(pids),
  fit: () => engine && engine.fit(),
});

function fitView() {
  if (engine) engine.fit();
}

function toggleWireframe() {
  if (engine) wireframe.value = engine.toggleWireframe();
}

function toggleEdges() {
  if (engine) edges.value = engine.toggleEdges();
}
</script>

<template>
  <div class="flex min-w-0 flex-1 flex-col bg-white">
    <div class="flex items-center gap-0.5 border-b border-zinc-200 bg-white px-2 py-1">
      <button
        type="button"
        title="Обновить предпросмотр"
        :disabled="!canRefresh"
        class="flex h-7 w-7 items-center justify-center rounded-md text-zinc-500 transition-colors hover:bg-zinc-100 hover:text-zinc-800 disabled:opacity-40"
        @click="emit('refresh')"
      >
        <Icon name="refresh" :size="15" />
      </button>
      <button
        type="button"
        title="Вписать модель в окно"
        class="flex h-7 w-7 items-center justify-center rounded-md text-zinc-500 transition-colors hover:bg-zinc-100 hover:text-zinc-800"
        @click="fitView"
      >
        <Icon name="fit" :size="15" />
      </button>
      <button
        type="button"
        title="Каркас"
        class="flex h-7 w-7 items-center justify-center rounded-md transition-colors"
        :class="wireframe ? 'bg-sky-100 text-sky-700' : 'text-zinc-500 hover:bg-zinc-100 hover:text-zinc-800'"
        @click="toggleWireframe"
      >
        <Icon name="wire" :size="15" />
      </button>
      <button
        type="button"
        title="Контуры рёбер"
        class="flex h-7 w-7 items-center justify-center rounded-md transition-colors"
        :class="edges ? 'bg-sky-100 text-sky-700' : 'text-zinc-500 hover:bg-zinc-100 hover:text-zinc-800'"
        @click="toggleEdges"
      >
        <Icon name="edges" :size="15" />
      </button>

      <span class="flex-1"></span>

      <button
        type="button"
        class="flex items-center gap-1.5 rounded-md border px-2 py-1 text-[11px] font-medium transition-colors"
        :class="textures ? 'border-sky-300 bg-sky-50 text-sky-700' : 'border-zinc-300 text-zinc-500 hover:bg-zinc-100'"
        title="Встраивать текстуры в предпросмотр (крупнее и медленнее)"
        @click="emit('toggle-textures')"
      >
        <Icon name="image" :size="13" />
        Текстуры
      </button>
    </div>

    <div ref="container" class="relative min-h-0 flex-1">
      <canvas ref="canvas" class="absolute inset-0 block h-full w-full"></canvas>

      <div
        v-if="status !== 'ready'"
        class="absolute inset-0 flex flex-col items-center justify-center gap-3 bg-white/90 p-8 text-center"
      >
        <template v-if="offline">
          <Icon name="cube" :size="28" class="text-zinc-300" />
          <p class="max-w-xs text-xs leading-relaxed text-zinc-500">
            Предпросмотр и экспорт работают из SketchUp: откройте диалог через
            меню Plugins → Web 3D Export.
          </p>
        </template>
        <template v-else-if="status === 'building' || status === 'assembling' || status === 'empty'">
          <span class="inline-block h-6 w-6 animate-spin rounded-full border-2 border-zinc-200 border-t-sky-600"></span>
          <div v-if="status === 'building'" class="w-56">
            <div class="h-1.5 overflow-hidden rounded-full bg-zinc-200">
              <div class="h-full rounded-full bg-sky-600 transition-all" :style="{ width: pct + '%' }"></div>
            </div>
            <p class="mt-1.5 truncate text-[11px] text-zinc-500">
              Построение предпросмотра… {{ pct }}%
            </p>
            <p v-if="current" class="truncate text-[11px] text-zinc-400">{{ current }}</p>
          </div>
          <p v-else class="text-xs text-zinc-500">Сборка сцены…</p>
        </template>
        <template v-else-if="status === 'empty_selection'">
          <Icon name="cube" :size="28" class="text-zinc-300" />
          <p class="max-w-xs text-xs leading-relaxed text-zinc-500">
            Режим «Только выделенное», но ничего не выделено.<br />
            Выделите объекты в модели — предпросмотр построится автоматически.
          </p>
        </template>
        <template v-else-if="status === 'too_large'">
          <Icon name="warn" :size="28" class="text-amber-500" />
          <p class="max-w-xs text-xs leading-relaxed text-zinc-600">
            Модель слишком велика для предпросмотра
            <span v-if="bytes">({{ formatBytes(bytes) }})</span>.<br />
            Выполните экспорт и откройте полный 3D-просмотр.
          </p>
        </template>
        <template v-else-if="status === 'error'">
          <Icon name="warn" :size="28" class="text-red-400" />
          <p class="max-w-sm break-words font-mono text-[11px] leading-relaxed text-red-600">
            {{ message || "Не удалось построить предпросмотр." }}
          </p>
        </template>
      </div>
    </div>

    <div class="flex items-center gap-3 border-t border-zinc-200 bg-zinc-50 px-3 py-1 text-[11px] text-zinc-500">
      <span v-if="objects !== null">{{ objects }} {{ plural(objects, "объект", "объекта", "объектов") }}</span>
      <span v-if="triangles !== null">
        {{ triangles.toLocaleString("ru-RU") }} {{ plural(triangles, "треугольник", "треугольника", "треугольников") }}
      </span>
      <span class="flex-1"></span>
      <span v-if="status === 'ready'" class="text-emerald-600">предпросмотр готов</span>
    </div>
  </div>
</template>
