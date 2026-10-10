<script setup>
import Icon from "./Icon.vue";

// Вкладка «Вид»: режим отображения, качество подачи материалов и
// интенсивности студийного света. Освещение и качество действуют в режиме
// «Фото»; в «Рисованном» они скрыты - там сцена заливается ровно.
const props = defineProps({
  mode: { type: String, default: "photo" },
  quality: { type: String, default: "high" },
  lighting: { type: Object, required: true },
});

defineEmits(["set-mode", "set-quality", "set-lighting", "reset"]);

const MODES = [
  { value: "photo", label: "Фото", icon: "image", hint: "Студийный свет, блики, отражения" },
  { value: "sketch", label: "Рисованное", icon: "edges", hint: "Плоские грани и контуры, как в SketchUp" },
];

const QUALITIES = [
  { value: "low", label: "Низкое" },
  { value: "medium", label: "Среднее" },
  { value: "high", label: "Высокое" },
];

const SLIDERS = [
  { name: "key", label: "Ключевой", min: 0, max: 1.5 },
  { name: "rim", label: "Контровой", min: 0, max: 1 },
  { name: "fill", label: "Заполняющий", min: 0, max: 1 },
  { name: "top", label: "Верхний", min: 0, max: 0.6 },
  { name: "env", label: "Окружение", min: 0, max: 1 },
  { name: "background", label: "Фон", min: 0.5, max: 1.2 },
];
</script>

<template>
  <div class="space-y-4 p-3">
    <section>
      <h3 class="mb-1.5 text-[11px] font-semibold uppercase tracking-wide text-zinc-500">Режим</h3>
      <div class="grid grid-cols-2 gap-1.5">
        <button
          v-for="m in MODES"
          :key="m.value"
          type="button"
          class="flex flex-col items-center gap-1 rounded-md border px-2 py-2 text-xs font-medium transition-colors"
          :class="mode === m.value
            ? 'border-sky-500 bg-sky-500/10 text-white'
            : 'border-white/10 bg-[#1b1c21] text-zinc-400 hover:text-zinc-200'"
          :title="m.hint"
          @click="$emit('set-mode', m.value)"
        >
          <Icon :name="m.icon" :size="15" />
          {{ m.label }}
        </button>
      </div>
    </section>

    <template v-if="mode === 'photo'">
      <section>
        <h3 class="mb-1.5 text-[11px] font-semibold uppercase tracking-wide text-zinc-500">
          Качество материалов
        </h3>
        <div class="grid grid-cols-3 gap-1.5">
          <button
            v-for="q in QUALITIES"
            :key="q.value"
            type="button"
            class="rounded-md border px-1 py-1.5 text-xs font-medium transition-colors"
            :class="quality === q.value
              ? 'border-sky-500 bg-sky-500/10 text-white'
              : 'border-white/10 bg-[#1b1c21] text-zinc-400 hover:text-zinc-200'"
            @click="$emit('set-quality', q.value)"
          >
            {{ q.label }}
          </button>
        </div>
        <p class="mt-1.5 text-[11px] leading-snug text-zinc-500">
          Высокое подбирает блеск и отражения по имени материала, низкое показывает плоские цвета.
        </p>
      </section>

      <section>
        <h3 class="mb-1.5 text-[11px] font-semibold uppercase tracking-wide text-zinc-500">
          Освещение
        </h3>
        <div class="space-y-2">
          <label v-for="s in SLIDERS" :key="s.name" class="block">
            <span class="flex items-baseline justify-between text-xs text-zinc-400">
              {{ s.label }}
              <span class="font-mono text-[11px] text-zinc-500">{{ lighting[s.name].toFixed(2) }}</span>
            </span>
            <input
              :value="lighting[s.name]"
              type="range"
              :min="s.min"
              :max="s.max"
              step="0.01"
              class="mt-0.5 w-full accent-sky-500"
              @input="$emit('set-lighting', { [s.name]: Number($event.target.value) })"
            />
          </label>
        </div>
        <button
          type="button"
          class="mt-2.5 flex w-full items-center justify-center gap-1.5 rounded-md border border-white/10 bg-[#1b1c21] py-1.5 text-xs font-medium text-zinc-300 transition-colors hover:text-white"
          @click="$emit('reset')"
        >
          <Icon name="refresh" :size="13" />
          Сбросить настройки
        </button>
      </section>
    </template>
  </div>
</template>
