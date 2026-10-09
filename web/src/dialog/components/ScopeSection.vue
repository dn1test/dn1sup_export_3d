<script setup>
// Выбор объёма экспорта. Счётчик выделения обновляется вживую
// (SelectionObserver -> receiveSelection).
const scope = defineModel("scope", { type: String, default: "all" });

defineProps({
  selectionCount: { type: Number, default: null },
  disabled: { type: Boolean, default: false },
});
</script>

<template>
  <section>
    <h2 class="mb-2 text-[11px] font-semibold uppercase tracking-wide text-zinc-500">Что экспортировать</h2>
    <div class="grid grid-cols-1 gap-2">
      <label
        class="flex cursor-pointer items-start gap-2.5 rounded-lg border bg-white p-2.5 transition-colors"
        :class="[
          scope === 'all' ? 'border-sky-500 ring-1 ring-sky-500' : 'border-zinc-300 hover:border-zinc-400',
          disabled ? 'pointer-events-none opacity-60' : '',
        ]"
      >
        <input v-model="scope" type="radio" value="all" class="mt-0.5 accent-sky-600" :disabled="disabled" />
        <span>
          <span class="block font-medium text-zinc-800">Вся модель</span>
          <span class="text-xs text-zinc-500">Все объекты модели; выделение подсвечивается в предпросмотре</span>
        </span>
      </label>

      <label
        class="flex items-start gap-2.5 rounded-lg border bg-white p-2.5 transition-colors"
        :class="[
          scope === 'selection' ? 'border-sky-500 ring-1 ring-sky-500' : 'border-zinc-300',
          disabled || selectionCount === 0 ? 'pointer-events-none opacity-60' : 'cursor-pointer hover:border-zinc-400',
        ]"
      >
        <input
          v-model="scope"
          type="radio"
          value="selection"
          class="mt-0.5 accent-sky-600"
          :disabled="disabled || selectionCount === 0"
        />
        <span>
          <span class="block font-medium text-zinc-800">
            Только выделенное
            <span
              v-if="typeof selectionCount === 'number'"
              class="ml-1 rounded-full bg-zinc-100 px-1.5 py-0.5 text-[10px] text-zinc-500"
            >
              {{ selectionCount }}
            </span>
          </span>
          <span class="text-xs text-zinc-500">
            {{ selectionCount === 0 ? "Ничего не выделено в модели" : "Следит за выделением: изменили выделение — предпросмотр обновится" }}
          </span>
        </span>
      </label>
    </div>
  </section>
</template>
