<script setup>
import Icon from "./Icon.vue";
import IconButton from "./IconButton.vue";

defineProps({
  modelName: { type: String, default: "3D-модель" },
  wireframe: { type: Boolean, default: false },
  edges: { type: Boolean, default: true },
  fullscreen: { type: Boolean, default: false },
  panelOpen: { type: Boolean, default: true },
});

defineEmits(["toggle-panel", "fit", "reset", "wire", "edges", "screenshot", "fullscreen", "help"]);
</script>

<template>
  <header class="flex h-12 shrink-0 items-center gap-0.5 border-b border-white/10 bg-[#26272d] px-2">
    <IconButton
      :title="panelOpen ? 'Скрыть панель объектов' : 'Показать панель объектов'"
      @click="$emit('toggle-panel')"
    >
      <Icon name="panel" />
    </IconButton>

    <div class="mx-1 flex min-w-0 items-center gap-2">
      <Icon name="cube" class="shrink-0 text-sky-400" :size="18" />
      <span class="min-w-0 truncate text-sm font-medium text-zinc-100" :title="modelName">{{ modelName }}</span>
    </div>

    <div class="flex-1"></div>

    <IconButton title="Вписать в окно (F)" @click="$emit('fit')">
      <Icon name="fit" />
    </IconButton>
    <IconButton title="Сбросить камеру (R)" @click="$emit('reset')">
      <Icon name="reset" />
    </IconButton>
    <IconButton title="Каркасный режим (W)" :active="wireframe" @click="$emit('wire')">
      <Icon name="wire" />
    </IconButton>
    <IconButton title="Контурные линии (E)" :active="edges" @click="$emit('edges')">
      <Icon name="edges" />
    </IconButton>

    <div class="mx-1 h-6 w-px bg-white/10"></div>

    <IconButton title="Сохранить снимок (PNG)" @click="$emit('screenshot')">
      <Icon name="camera" />
    </IconButton>
    <IconButton
      :title="fullscreen ? 'Выйти из полноэкранного режима' : 'Во весь экран'"
      @click="$emit('fullscreen')"
    >
      <Icon :name="fullscreen ? 'minimize' : 'maximize'" />
    </IconButton>
    <IconButton title="Справка" @click="$emit('help')">
      <Icon name="help" />
    </IconButton>
  </header>
</template>
