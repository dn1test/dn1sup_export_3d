<script setup>
defineProps({
  title: { type: String, default: "" },
  active: { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
});
</script>

<template>
  <button
    type="button"
    :title="title"
    :disabled="disabled"
    class="flex h-8 w-8 items-center justify-center rounded-md text-zinc-300 transition-colors hover:bg-white/10 hover:text-white disabled:opacity-40"
    :class="active ? 'bg-sky-600/80 text-white hover:bg-sky-600 hover:text-white' : ''"
  >
    <slot />
  </button>
</template>
