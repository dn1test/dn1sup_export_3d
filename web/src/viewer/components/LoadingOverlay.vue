<script setup>
import { computed } from "vue";

const props = defineProps({
  // null | {loaded, total}
  progress: { type: Object, default: null },
  fileName: { type: String, default: "" },
});

const percent = computed(() => {
  if (!props.progress || !props.progress.total) return null;
  return Math.min(100, Math.round((props.progress.loaded / props.progress.total) * 100));
});
</script>

<template>
  <div class="absolute inset-0 z-20 flex flex-col items-center justify-center gap-3 bg-[#1e1f24]/90">
    <div class="h-10 w-10 animate-spin rounded-full border-[3px] border-zinc-600 border-t-sky-500"></div>
    <p class="text-sm text-zinc-300">Загрузка модели…</p>
    <p v-if="fileName" class="max-w-xs truncate px-4 text-xs text-zinc-500">{{ fileName }}</p>
    <template v-if="percent !== null">
      <div class="h-1 w-48 overflow-hidden rounded bg-zinc-700">
        <div class="h-full bg-sky-500 transition-all" :style="{ width: percent + '%' }"></div>
      </div>
      <p class="text-xs text-zinc-500">{{ percent }}%</p>
    </template>
  </div>
</template>
