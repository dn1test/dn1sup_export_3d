<script setup>
import { computed } from "vue";
import { plural } from "../../shared/plural.js";

const props = defineProps({
  objectsCount: { type: Number, default: 0 },
  triangles: { type: Number, default: 0 },
});

const objectsLabel = computed(() =>
  `${props.objectsCount} ${plural(props.objectsCount, "объект", "объекта", "объектов")}`
);
const trianglesLabel = computed(
  () =>
    `${props.triangles.toLocaleString("ru-RU")} ${plural(props.triangles, "треугольник", "треугольника", "треугольников")}`
);
</script>

<template>
  <div
    class="flex h-7 shrink-0 items-center justify-between gap-4 border-t border-white/10 bg-[#26272d] px-3 text-[11px] text-zinc-400"
  >
    <span class="shrink-0">
      {{ objectsLabel }} · {{ trianglesLabel }}
    </span>
    <span class="hidden truncate md:inline">
      ЛКМ — выбрать · двойной клик — приблизить · зажатая ЛКМ — вращение · ПКМ — панорама · колесо — масштаб
    </span>
  </div>
</template>
