<script setup>
import { computed } from "vue";
import Icon from "./Icon.vue";

// Рекурсивный узел дерева объектов.
defineOptions({ name: "TreeNode" });

const props = defineProps({
  node: { type: Object, required: true },
  depth: { type: Number, default: 0 },
  // Контекст дерева: состояние (раскрыт/выбран/скрыт) и обработчики.
  ctx: { type: Object, required: true },
});

const hasChildren = computed(() => props.node.children.length > 0);
const open = computed(() => hasChildren.value && props.ctx.isOpen(props.node.pid));
const typeLetter = computed(() => (props.node.type || "O").charAt(0).toUpperCase());
const badgeClass = computed(() => {
  const t = props.node.type;
  if (t === "Group") return "bg-emerald-700/70 text-emerald-100";
  if (t === "ComponentInstance") return "bg-sky-700/70 text-sky-100";
  return "bg-zinc-600 text-zinc-100";
});
</script>

<template>
  <div>
    <div
      class="group flex cursor-pointer items-center gap-1 rounded pr-0.5"
      :class="ctx.isSelected(node.pid) ? 'bg-sky-600/30' : 'hover:bg-white/5'"
      :style="{ paddingLeft: depth * 14 + 4 + 'px' }"
      :title="`${node.name} (${node.pid})`"
      @click="ctx.select(node.pid)"
    >
      <button
        v-if="hasChildren"
        type="button"
        class="flex h-5 w-5 shrink-0 items-center justify-center text-zinc-500 hover:text-zinc-200"
        :title="open ? 'Свернуть' : 'Развернуть'"
        @click.stop="ctx.toggle(node.pid)"
      >
        <Icon name="chevron" :size="12" class="transition-transform" :class="open ? 'rotate-90' : ''" />
      </button>
      <span v-else class="w-5 shrink-0"></span>

      <span
        class="flex h-4 w-4 shrink-0 items-center justify-center rounded-sm text-[9px] font-bold"
        :class="badgeClass"
        :title="node.type || 'Объект'"
      >
        {{ typeLetter }}
      </span>

      <span
        class="min-w-0 flex-1 truncate py-0.5 text-xs"
        :class="ctx.isHidden(node.pid) ? 'text-zinc-500 line-through' : 'text-zinc-200'"
      >
        {{ node.name }}
      </span>

      <button
        type="button"
        class="flex h-6 w-6 shrink-0 items-center justify-center rounded text-zinc-500 hover:text-zinc-200"
        :class="ctx.isHidden(node.pid) ? '' : 'opacity-0 group-hover:opacity-100'"
        :title="ctx.isHidden(node.pid) ? 'Показать' : 'Скрыть'"
        @click.stop="ctx.toggleEye(node.pid)"
      >
        <Icon :name="ctx.isHidden(node.pid) ? 'eye-off' : 'eye'" :size="13" />
      </button>
    </div>

    <template v-if="open">
      <TreeNode v-for="child in node.children" :key="child.pid" :node="child" :depth="depth + 1" :ctx="ctx" />
    </template>
  </div>
</template>
