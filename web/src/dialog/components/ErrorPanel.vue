<script setup>
defineProps({
  message: { type: String, default: null },
});
</script>

<template>
  <section class="rounded-lg border border-red-200 bg-red-50 p-3">
    <p class="text-xs font-semibold text-red-800">Экспорт не выполнен</p>
    <p class="mt-1 break-words text-[11px] leading-snug text-red-700">
      {{ message || "Неизвестная ошибка. Подробности — в консоли Ruby (Window → Ruby Console)." }}
    </p>
  </section>
</template>
