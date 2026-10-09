<script setup>
import { computed } from "vue";

// Куда и в каком виде сохранять. Пользователь указывает только папку — имя
// файла Ruby собирает сам из имени модели (латиница, см. Filename.sanitize).
const folder = defineModel("folder", { type: String, default: "" });
const singleFile = defineModel("singleFile", { type: Boolean, default: true });
const webPackage = defineModel("webPackage", { type: Boolean, default: true });
const includeHidden = defineModel("includeHidden", { type: Boolean, default: false });

const props = defineProps({
  disabled: { type: Boolean, default: false },
  outputName: { type: String, default: "" },
});
const emit = defineEmits(["browse"]);

// Ruby присылает готовое латинское имя GLB (state.output_name); из него же
// считаются имена остальных артефактов.
const glbName = computed(() => props.outputName || "<имя модели>.glb");
const htmlName = computed(() => `${glbName.value.replace(/\.glb$/i, "")}.html`);
</script>

<template>
  <section>
    <h2 class="mb-2 text-[11px] font-semibold uppercase tracking-wide text-zinc-500">Куда сохранить</h2>
    <div class="flex gap-2">
      <input
        v-model="folder"
        type="text"
        spellcheck="false"
        placeholder="C:\путь\к\папке"
        class="min-w-0 flex-1 rounded-md border border-zinc-300 bg-white px-2.5 py-1.5 text-xs text-zinc-800 placeholder-zinc-400 focus:border-sky-500 focus:outline-none focus:ring-1 focus:ring-sky-500"
        :disabled="disabled"
      />
      <button
        type="button"
        :disabled="disabled"
        class="shrink-0 rounded-md border border-zinc-300 bg-white px-3 py-1.5 text-xs font-medium text-zinc-700 hover:bg-zinc-100 disabled:opacity-50"
        @click="emit('browse')"
      >
        Обзор…
      </button>
    </div>
    <p class="mt-1.5 text-[11px] leading-snug text-zinc-500">
      Имя файла: <span class="font-medium text-zinc-700">{{ glbName }}</span>
      — создаётся из имени модели, только латиница
    </p>

    <div class="mt-2.5 space-y-1.5">
      <label class="flex cursor-pointer items-start gap-2 text-xs text-zinc-700">
        <input v-model="singleFile" type="checkbox" class="mt-0.5 accent-sky-600" :disabled="disabled" />
        <span>
          Один HTML-файл со встроенной моделью
          <span class="block text-[11px] leading-snug text-zinc-500">
            {{ htmlName }} открывается двойным кликом в любом браузере — удобно отправить заказчику
          </span>
        </span>
      </label>
      <label class="flex cursor-pointer items-start gap-2 text-xs text-zinc-700">
        <input v-model="webPackage" type="checkbox" class="mt-0.5 accent-sky-600" :disabled="disabled" />
        <span>
          Веб-пакет для сайта
          <span class="block text-[11px] leading-snug text-zinc-500">
            Папка с index.html и model.glb — для загрузки на хостинг
          </span>
        </span>
      </label>
      <label class="flex cursor-pointer items-center gap-2 text-xs text-zinc-700">
        <input v-model="includeHidden" type="checkbox" class="accent-sky-600" :disabled="disabled" />
        Включая скрытую геометрию
      </label>
      <p v-if="!singleFile && !webPackage" class="text-[11px] text-zinc-500">
        Будет записан только .glb — модель без просмотрщика.
      </p>
    </div>
  </section>
</template>
