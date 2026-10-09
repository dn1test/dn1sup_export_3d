<script setup>
import Icon from "./Icon.vue";

defineEmits(["close"]);

const mouse = [
  ["ЛКМ", "выбрать объект"],
  ["Двойной клик", "приблизить к объекту"],
  ["Зажатая ЛКМ", "вращение"],
  ["ПКМ", "панорама"],
  ["Колесо", "масштаб"],
];

const keys = [
  ["F", "вписать в окно"],
  ["R", "сбросить камеру"],
  ["W", "каркасный режим"],
  ["E", "контурные линии"],
  ["Esc", "снять выделение / закрыть"],
  ["?", "справка"],
];
</script>

<template>
  <div class="absolute inset-0 z-30 flex items-center justify-center bg-black/50 p-6" @click.self="$emit('close')">
    <div class="w-80 rounded-xl border border-white/10 bg-[#2a2b31] p-5 shadow-xl">
      <div class="flex items-center justify-between">
        <h2 class="text-sm font-semibold text-zinc-100">Управление</h2>
        <button
          type="button"
          class="flex h-7 w-7 items-center justify-center rounded-md text-zinc-400 hover:bg-white/10 hover:text-white"
          title="Закрыть"
          @click="$emit('close')"
        >
          <Icon name="close" :size="14" />
        </button>
      </div>

      <h3 class="mt-3 text-[11px] font-semibold uppercase tracking-wide text-zinc-500">Мышь</h3>
      <div class="mt-1.5 space-y-1.5">
        <div v-for="[k, v] in mouse" :key="k" class="flex items-center justify-between gap-3 text-xs">
          <span class="text-zinc-300">{{ k }}</span>
          <span class="text-right text-zinc-500">{{ v }}</span>
        </div>
      </div>

      <h3 class="mt-4 text-[11px] font-semibold uppercase tracking-wide text-zinc-500">Клавиши</h3>
      <div class="mt-1.5 space-y-1.5">
        <div v-for="[k, v] in keys" :key="k" class="flex items-center justify-between gap-3 text-xs">
          <kbd class="rounded bg-white/10 px-1.5 py-0.5 font-mono text-[10px] text-zinc-200">{{ k }}</kbd>
          <span class="text-right text-zinc-500">{{ v }}</span>
        </div>
      </div>
    </div>
  </div>
</template>
