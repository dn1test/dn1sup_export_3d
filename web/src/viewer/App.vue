<script setup>
import { onBeforeUnmount, onMounted, ref } from "vue";
import ViewerEngine from "./engine/ViewerEngine.js";
import { callSketchUp } from "../shared/bridge.js";
import AppHeader from "./components/AppHeader.vue";
import SidePanel from "./components/SidePanel.vue";
import StatusBar from "./components/StatusBar.vue";
import LoadingOverlay from "./components/LoadingOverlay.vue";
import ErrorOverlay from "./components/ErrorOverlay.vue";
import HelpOverlay from "./components/HelpOverlay.vue";

// Single-file HTML (собирается расширением) внедряет модель и её имя глобалом;
// обычный пакет берёт model.glb из ?model= или из соседней папки.
const boot = typeof window !== "undefined" ? window.__VIEWER_BOOT || null : null;
const modelUrl =
  boot?.model || new URLSearchParams(location.search).get("model") || "./model.glb";
const modelName = boot?.name || modelFileName(modelUrl);

function modelFileName(url) {
  if (/^data:/i.test(url)) return "model.glb";
  try {
    const name = decodeURIComponent(url.split(/[\\/]/).pop() || "");
    return name || "model.glb";
  } catch {
    return "model.glb";
  }
}

const canvasEl = ref(null);
const stageEl = ref(null);

const phase = ref("loading"); // loading | ready | error
const loadProgress = ref(null); // {loaded, total} | null
const errorText = ref("");
const objectsCount = ref(0);
const triangles = ref(0);
const tree = ref([]);
const visibility = ref({});
const selectedPid = ref(null);
const selectedExtras = ref(null);
const wireframe = ref(false);
const edges = ref(true);
const panelOpen = ref(true);
const activeTab = ref("objects");
const filterQuery = ref("");
const helpOpen = ref(false);
const isFullscreen = ref(false);

let engine = null;
let resizeObserver = null;

onMounted(() => {
  engine = new ViewerEngine(canvasEl.value);

  resizeObserver = new ResizeObserver(() => engine.resize());
  resizeObserver.observe(stageEl.value);
  engine.resize();

  engine.on("loadStart", () => {
    phase.value = "loading";
    loadProgress.value = null;
  });
  engine.on("progress", (p) => {
    loadProgress.value = p;
  });
  engine.on("viewerReady", ({ objects, triangles: tri }) => {
    phase.value = "ready";
    objectsCount.value = objects;
    triangles.value = tri;
    tree.value = engine.getTree();
    const vis = {};
    const walk = (nodes) => nodes.forEach((n) => {
      vis[n.pid] = true;
      walk(n.children);
    });
    walk(tree.value);
    visibility.value = vis;
    // Мост с Ruby: тот же сигнал, что посылал старый viewer.js.
    callSketchUp("viewer_ready", String(objects));
  });
  engine.on("loadError", ({ error }) => {
    phase.value = "error";
    errorText.value = error;
  });
  engine.on("objectSelected", ({ pid, extras, chain }) => {
    selectedPid.value = pid;
    selectedExtras.value = extras;
    // Выбор из 3D - пользователь разглядывает объект: показать его свойства.
    // Клик по дереву оставляет вкладку дерева (там и происходит выбор).
    if (chain) activeTab.value = "properties";
    // Из 3D приходит цепочка pid (деталь -> инстанс); Ruby выберет первый
    // существующий. Из дерева - один pid.
    callSketchUp("object_selected", ...(chain || [pid]));
  });
  engine.on("selectionCleared", () => {
    selectedPid.value = null;
    selectedExtras.value = null;
  });
  engine.on("objectVisibilityChanged", ({ pid, visible }) => {
    visibility.value = { ...visibility.value, [pid]: visible };
  });
  engine.on("wireframe", (v) => {
    wireframe.value = v;
  });
  engine.on("edges", (v) => {
    edges.value = v;
  });

  engine.loadModel(modelUrl);
  document.title = `${modelName} — 3D-просмотр`;

  // Обратная совместимость: публичный API из README (execute_script из Ruby).
  window.viewer = {
    loadModel: (url) => engine.loadModel(url),
    selectObject: (pid) => engine.selectObject(pid),
    focusObject: (pid) => engine.focusObject(pid),
    getObject: (pid) => engine.getObject(pid),
    setShowObject: (pid, visible) => engine.setShowObject(pid, visible),
    clearSelection: () => engine.clearSelection(),
    toggleEdges: () => engine.toggleEdges(),
    fit: () => engine.fit(),
    reset: () => engine.reset(),
    on: (event, cb) => engine.on(event, cb),
    get selectedPid() {
      return engine.selectedPid;
    },
  };

  window.addEventListener("keydown", onKeydown);
  document.addEventListener("fullscreenchange", onFullscreenChange);
});

onBeforeUnmount(() => {
  window.removeEventListener("keydown", onKeydown);
  document.removeEventListener("fullscreenchange", onFullscreenChange);
  if (resizeObserver) resizeObserver.disconnect();
  if (engine) engine.dispose();
  delete window.viewer;
});

// Горячие клавиши по e.code - не зависят от раскладки (Ф/R и т.д.).
function onKeydown(e) {
  const t = e.target;
  if (t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.isContentEditable)) return;
  if (e.ctrlKey || e.metaKey || e.altKey) return;
  switch (e.code) {
    case "KeyF":
      engine.fit();
      break;
    case "KeyR":
      engine.reset();
      break;
    case "KeyW":
      engine.toggleWireframe();
      break;
    case "KeyE":
      engine.toggleEdges();
      break;
    case "Escape":
      if (helpOpen.value) helpOpen.value = false;
      else engine.clearSelection();
      break;
    default:
      if (e.key === "?") helpOpen.value = !helpOpen.value;
  }
}

function onFullscreenChange() {
  isFullscreen.value = !!document.fullscreenElement;
}

// ------------------------------------------------------------- действия

function selectFromTree(pid) {
  engine.selectObject(pid);
}

function toggleVisibility(pid) {
  engine.setShowObject(pid, visibility.value[pid] === false);
}

function focusSelected() {
  if (selectedPid.value) engine.focusObject(selectedPid.value);
}

function togglePanel() {
  panelOpen.value = !panelOpen.value;
}

async function screenshot() {
  try {
    const blob = await engine.screenshot();
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `${modelName}.png`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 5000);
  } catch (err) {
    console.error("Screenshot failed", err);
  }
}

function toggleFullscreen() {
  if (document.fullscreenElement) document.exitFullscreen();
  else document.documentElement.requestFullscreen();
}

function retryLoad() {
  errorText.value = "";
  engine.loadModel(modelUrl);
}

const singleFileName = (() => {
  if (boot?.model) return `${String(modelName).replace(/\.glb$/i, "")}.html`;
  return "";
})();
</script>

<template>
  <div class="flex h-full flex-col bg-white text-zinc-200">
    <AppHeader
      :model-name="modelName"
      :wireframe="wireframe"
      :edges="edges"
      :fullscreen="isFullscreen"
      :panel-open="panelOpen"
      @toggle-panel="togglePanel"
      @fit="engine.fit()"
      @reset="engine.reset()"
      @wire="engine.toggleWireframe()"
      @edges="engine.toggleEdges()"
      @screenshot="screenshot"
      @fullscreen="toggleFullscreen"
      @help="helpOpen = true"
    />

    <div class="flex min-h-0 flex-1">
      <SidePanel
        v-show="panelOpen"
        v-model:active-tab="activeTab"
        v-model:filter-query="filterQuery"
        :tree="tree"
        :visibility="visibility"
        :selected-pid="selectedPid"
        :selected-extras="selectedExtras"
        @select="selectFromTree"
        @toggle-visibility="toggleVisibility"
        @focus="focusSelected"
      />

      <main ref="stageEl" class="relative min-w-0 flex-1">
        <canvas ref="canvasEl" class="absolute inset-0 block h-full w-full"></canvas>

        <LoadingOverlay
          v-if="phase === 'loading'"
          :progress="loadProgress"
          :file-name="modelFileName(modelUrl)"
        />
        <ErrorOverlay
          v-if="phase === 'error'"
          :error="errorText"
          :single-file-name="singleFileName"
          @retry="retryLoad"
        />
        <HelpOverlay v-if="helpOpen" @close="helpOpen = false" />
      </main>
    </div>

    <StatusBar :objects-count="objectsCount" :triangles="triangles" />
  </div>
</template>
