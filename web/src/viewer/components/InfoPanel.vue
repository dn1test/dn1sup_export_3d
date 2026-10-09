<script setup>
import { computed } from "vue";
import Icon from "./Icon.vue";

const props = defineProps({
  extras: { type: Object, default: null },
});

defineEmits(["focus"]);

const TYPE_RU = {
  ComponentInstance: "Компонент",
  Group: "Группа",
  Image: "Изображение",
};

const typeRu = computed(
  () => TYPE_RU[props.extras?.entity_type] || props.extras?.entity_type || "—"
);
</script>

<template>
  <div class="p-3">
    <p v-if="!extras" class="text-xs leading-relaxed text-zinc-500">
      Объект не выбран. Кликните по модели или выберите объект на вкладке «Объекты».
    </p>

    <template v-else>
      <dl class="space-y-2.5 text-xs">
        <div class="flex items-start justify-between gap-3">
          <dt class="shrink-0 text-zinc-500">Имя</dt>
          <dd class="break-words text-right text-zinc-200">{{ extras.name || "—" }}</dd>
        </div>
        <div class="flex items-start justify-between gap-3">
          <dt class="shrink-0 text-zinc-500">Тип</dt>
          <dd class="text-right text-zinc-200">{{ typeRu }}</dd>
        </div>
        <div class="flex items-start justify-between gap-3">
          <dt class="shrink-0 text-zinc-500">Persistent ID</dt>
          <dd class="break-all text-right font-mono text-zinc-200">{{ extras.persistent_id }}</dd>
        </div>
        <div class="flex items-start justify-between gap-3">
          <dt class="shrink-0 text-zinc-500">Слой</dt>
          <dd class="break-words text-right text-zinc-200">{{ extras.layer || "—" }}</dd>
        </div>
      </dl>

      <button
        type="button"
        class="mt-4 flex w-full items-center justify-center gap-1.5 rounded-md bg-sky-600/90 py-1.5 text-xs font-medium text-white transition-colors hover:bg-sky-600"
        @click="$emit('focus')"
      >
        <Icon name="focus" :size="13" />
        Приблизить
      </button>
    </template>
  </div>
</template>
