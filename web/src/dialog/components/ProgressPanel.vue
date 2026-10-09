<script setup>
// Панель хода экспорта: процент, стадия, имя обрабатываемого объекта,
// кнопка отмены (срабатывает между шагами пошагового экспорта).
defineProps({
  pct: { type: Number, default: 0 },
  stage: { type: String, default: "" },
  current: { type: String, default: null },
  label: { type: String, default: "Экспорт" },
});
defineEmits(["cancel"]);
</script>

<template>
  <section class="rounded-lg border border-sky-200 bg-sky-50 p-3">
    <div class="flex items-center gap-2">
      <span class="text-xs font-semibold text-sky-900">{{ label }}</span>
      <span class="flex-1"></span>
      <span class="font-mono text-xs text-sky-800">{{ pct }}%</span>
    </div>
    <div class="mt-2 h-1.5 overflow-hidden rounded-full bg-sky-100">
      <div class="h-full rounded-full bg-sky-600 transition-all" :style="{ width: pct + '%' }"></div>
    </div>
    <div class="mt-2 flex items-center gap-2">
      <p class="min-w-0 flex-1 truncate text-[11px] text-sky-800">
        {{ stage }}<template v-if="current">: {{ current }}</template>
      </p>
      <button
        type="button"
        class="shrink-0 rounded-md border border-sky-300 bg-white px-2.5 py-1 text-[11px] font-medium text-sky-800 hover:bg-sky-100"
        @click="emit('cancel')"
      >
        Отмена
      </button>
    </div>
  </section>
</template>
