<script setup>
import Icon from "./Icon.vue";
import ObjectTree from "./ObjectTree.vue";
import InfoPanel from "./InfoPanel.vue";

defineProps({
  tree: { type: Array, default: () => [] },
  visibility: { type: Object, default: () => ({}) },
  selectedPid: { type: String, default: null },
  selectedExtras: { type: Object, default: null },
  activeTab: { type: String, default: "objects" },
  filterQuery: { type: String, default: "" },
});

defineEmits(["select", "toggle-visibility", "focus", "update:activeTab", "update:filterQuery"]);
</script>

<template>
  <aside class="flex w-72 shrink-0 flex-col border-r border-white/10 bg-[#232429]">
    <div class="flex shrink-0 border-b border-white/10">
      <button
        type="button"
        class="flex-1 border-b-2 px-3 py-2 text-xs font-medium transition-colors"
        :class="activeTab === 'objects'
          ? 'border-sky-500 bg-white/5 text-white'
          : 'border-transparent text-zinc-400 hover:text-zinc-200'"
        @click="$emit('update:activeTab', 'objects')"
      >
        Объекты
      </button>
      <button
        type="button"
        class="flex-1 border-b-2 px-3 py-2 text-xs font-medium transition-colors"
        :class="activeTab === 'properties'
          ? 'border-sky-500 bg-white/5 text-white'
          : 'border-transparent text-zinc-400 hover:text-zinc-200'"
        @click="$emit('update:activeTab', 'properties')"
      >
        Свойства
      </button>
    </div>

    <div v-show="activeTab === 'objects'" class="shrink-0 p-2">
      <div class="relative">
        <Icon name="search" :size="13" class="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-zinc-500" />
        <input
          :value="filterQuery"
          type="text"
          spellcheck="false"
          placeholder="Поиск объектов…"
          class="w-full rounded-md border border-white/10 bg-[#1b1c21] py-1.5 pl-8 pr-2 text-xs text-zinc-200 placeholder-zinc-500 focus:border-sky-600 focus:outline-none"
          @input="$emit('update:filterQuery', $event.target.value)"
        />
      </div>
    </div>

    <div class="thin-scroll min-h-0 flex-1 overflow-y-auto">
      <ObjectTree
        v-show="activeTab === 'objects'"
        :tree="tree"
        :visibility="visibility"
        :selected-pid="selectedPid"
        :filter-query="filterQuery"
        @select="$emit('select', $event)"
        @toggle-visibility="$emit('toggle-visibility', $event)"
      />
      <InfoPanel
        v-if="activeTab === 'properties'"
        :extras="selectedExtras"
        @focus="$emit('focus')"
      />
    </div>
  </aside>
</template>
