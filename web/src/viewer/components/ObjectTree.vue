<script setup>
import { computed, reactive, ref, watch } from "vue";
import TreeNode from "./TreeNode.vue";

const props = defineProps({
  tree: { type: Array, default: () => [] },
  visibility: { type: Object, default: () => ({}) },
  selectedPid: { type: String, default: null },
  filterQuery: { type: String, default: "" },
});

const emit = defineEmits(["select", "toggle-visibility"]);

// pid -> родительский pid (для авто-раскрытия предков при выборе).
const parentOf = computed(() => {
  const map = new Map();
  const walk = (nodes, parent) => {
    nodes.forEach((n) => {
      map.set(n.pid, parent);
      walk(n.children, n.pid);
    });
  };
  walk(props.tree, null);
  return map;
});

// Раскрытые ветки. Новое дерево (загрузка модели) сбрасывает состояние.
const expanded = ref(new Set());
watch(
  () => props.tree,
  () => {
    expanded.value = new Set();
  }
);

// Пометка узлов, совпадающих с поиском (вместе с их предками).
const matches = computed(() => {
  const q = props.filterQuery.trim().toLowerCase();
  if (!q) return null;
  const keep = new Set();
  const walk = (nodes) => {
    let any = false;
    for (const n of nodes) {
      const self =
        n.name.toLowerCase().includes(q) || (n.type || "").toLowerCase().includes(q);
      const child = walk(n.children);
      if (self || child) {
        keep.add(n.pid);
        any = true;
      }
    }
    return any;
  };
  walk(props.tree);
  return keep;
});

// При поиске остаются только совпавшие ветки.
const visibleTree = computed(() => {
  if (!matches.value) return props.tree;
  const filter = (nodes) =>
    nodes.filter((n) => matches.value.has(n.pid)).map((n) => ({ ...n, children: filter(n.children) }));
  return filter(props.tree);
});

// Авто-раскрытие предков выбранного узла.
watch(
  () => props.selectedPid,
  (pid) => {
    if (!pid) return;
    const next = new Set(expanded.value);
    let p = parentOf.value.get(pid) || null;
    while (p) {
      next.add(p);
      p = parentOf.value.get(p) || null;
    }
    expanded.value = next;
  }
);

const ctx = reactive({
  filterActive: () => !!matches.value,
  isOpen: (pid) => (matches.value ? true : expanded.value.has(pid)),
  isSelected: (pid) => props.selectedPid === pid,
  isHidden: (pid) => props.visibility[pid] === false,
  toggle: (pid) => {
    const next = new Set(expanded.value);
    if (next.has(pid)) next.delete(pid);
    else next.add(pid);
    expanded.value = next;
  },
  select: (pid) => emit("select", pid),
  toggleEye: (pid) => emit("toggle-visibility", pid),
});
</script>

<template>
  <div class="select-none px-1 py-1">
    <p v-if="!visibleTree.length" class="px-2 py-6 text-center text-xs text-zinc-500">
      {{ filterQuery ? "Ничего не найдено" : "Объекты не найдены" }}
    </p>
    <TreeNode v-for="node in visibleTree" :key="node.pid" :node="node" :depth="0" :ctx="ctx" />
  </div>
</template>
