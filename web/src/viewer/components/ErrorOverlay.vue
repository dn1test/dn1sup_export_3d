<script setup>
import { computed } from "vue";
import Icon from "./Icon.vue";

const props = defineProps({
  error: { type: String, default: "" },
  // Имя single-file-страницы для подсказки, например "кухня.html"
  singleFileName: { type: String, default: "" },
});

const emit = defineEmits(["retry"]);

const isFileProtocol = computed(() => location.protocol === "file:");
</script>

<template>
  <div class="absolute inset-0 z-20 flex items-center justify-center bg-[#1e1f24]/90 p-6">
    <div class="max-w-md rounded-xl border border-red-900/50 bg-[#2a2b31] p-6 text-center shadow-xl">
      <Icon name="warn" :size="36" class="mx-auto text-red-400" />
      <h2 class="mt-3 text-base font-semibold text-zinc-100">Не удалось загрузить модель</h2>
      <p class="mt-1 break-all text-xs text-zinc-400">{{ error }}</p>

      <div
        v-if="isFileProtocol"
        class="mt-4 rounded-lg bg-[#232429] p-3 text-left text-xs leading-relaxed text-zinc-400"
      >
        Страница открыта как локальный файл, а браузеры не позволяют веб-страницам читать
        соседние файлы с диска.
        <template v-if="singleFileName">
          Откройте файл <span class="font-semibold text-zinc-200">{{ singleFileName }}</span> —
          модель встроена в него и открывается двойным кликом.
        </template>
        <template v-else>
          Разместите папку на любом веб-хостинге или откройте просмотр из SketchUp.
        </template>
      </div>

      <button
        type="button"
        class="mt-4 rounded-md bg-sky-600 px-4 py-1.5 text-xs font-medium text-white transition-colors hover:bg-sky-500"
        @click="emit('retry')"
      >
        Повторить
      </button>
    </div>
  </div>
</template>
