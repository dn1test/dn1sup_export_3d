<script setup>
import { computed } from "vue";
import Icon from "../../viewer/components/Icon.vue";
import { formatBytes } from "../../shared/format.js";
import { plural } from "../../shared/plural.js";

// Результат экспорта: статистика, созданные артефакты, предупреждения
// экспортёра (заменённые текстуры и т.п.) и действия.
const props = defineProps({
  stats: { type: Object, default: null },
  warnings: { type: Array, default: () => [] },
  glbName: { type: String, default: null },
  webDirName: { type: String, default: null },
  singleFileName: { type: String, default: null },
  singleFileBytes: { type: Number, default: null },
});

defineEmits(["open-viewer", "open-folder", "open-html"]);

const geometryLine = computed(() => {
  const s = props.stats;
  if (!s) return "";
  return (
    `${s.faces.toLocaleString("ru-RU")} ${plural(s.faces, "грань", "грани", "граней")}, ` +
    `${s.triangles.toLocaleString("ru-RU")} ${plural(s.triangles, "треугольник", "треугольника", "треугольников")}`
  );
});

const materialsLine = computed(() => {
  const s = props.stats;
  if (!s) return "";
  return (
    `${s.materials} ${plural(s.materials, "материал", "материала", "материалов")}, ` +
    `${s.textures} ${plural(s.textures, "текстура", "текстуры", "текстур")}`
  );
});

const canOpenViewer = computed(() => !!props.webDirName || !!props.singleFileName);
const canOpenFolder = computed(() => !!props.webDirName || !!props.glbName);
</script>

<template>
  <section class="rounded-lg border border-emerald-200 bg-emerald-50 p-3">
    <div class="flex items-center gap-1.5">
      <Icon name="check" :size="14" class="text-emerald-600" />
      <span class="text-xs font-semibold text-emerald-900">Экспорт выполнен</span>
      <span class="flex-1"></span>
      <span class="text-[11px] text-emerald-700">за {{ stats.seconds }} с</span>
    </div>

    <dl class="mt-2 grid grid-cols-2 gap-x-3 gap-y-1 text-[11px] text-zinc-700">
      <dt class="text-zinc-500">Геометрия</dt>
      <dd class="text-right font-mono">{{ geometryLine }}</dd>
      <dt class="text-zinc-500">Материалы</dt>
      <dd class="text-right font-mono">{{ materialsLine }}</dd>
      <dt class="text-zinc-500">Размер GLB</dt>
      <dd class="text-right font-mono">{{ formatBytes(stats.bytes) }}</dd>
      <template v-if="singleFileName">
        <dt class="text-zinc-500">Один HTML</dt>
        <dd class="text-right font-mono">
          {{ singleFileName }}<span v-if="singleFileBytes"> · {{ formatBytes(singleFileBytes) }}</span>
        </dd>
      </template>
      <template v-if="webDirName">
        <dt class="text-zinc-500">Веб-пакет</dt>
        <dd class="text-right font-mono">{{ webDirName }}</dd>
      </template>
    </dl>

    <div v-if="warnings.length" class="mt-2 rounded-md border border-amber-200 bg-amber-50 p-2">
      <p class="text-[11px] font-semibold text-amber-800">Замечания:</p>
      <ul class="mt-1 list-disc space-y-0.5 pl-4 text-[11px] leading-snug text-amber-800">
        <li v-for="(warning, index) in warnings" :key="index">{{ warning }}</li>
      </ul>
    </div>

    <div class="mt-3 flex flex-wrap gap-2">
      <button
        type="button"
        :disabled="!canOpenViewer"
        class="rounded-md bg-sky-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-sky-500 disabled:opacity-50"
        @click="emit('open-viewer')"
      >
        Открыть 3D-просмотр
      </button>
      <button
        type="button"
        :disabled="!singleFileName"
        class="rounded-md border border-zinc-300 bg-white px-3 py-1.5 text-xs font-medium text-zinc-700 hover:bg-zinc-100 disabled:opacity-50"
        @click="emit('open-html')"
      >
        Открыть HTML в браузере
      </button>
      <button
        type="button"
        :disabled="!canOpenFolder"
        class="rounded-md border border-zinc-300 bg-white px-3 py-1.5 text-xs font-medium text-zinc-700 hover:bg-zinc-100 disabled:opacity-50"
        @click="emit('open-folder')"
      >
        Открыть папку
      </button>
    </div>
  </section>
</template>
