<script setup>
import { computed, onBeforeUnmount, onMounted, reactive, ref, watch } from "vue";
import { callSketchUp, inSketchUp } from "../shared/bridge.js";
import PreviewPane from "./components/PreviewPane.vue";
import ScopeSection from "./components/ScopeSection.vue";
import OutputSection from "./components/OutputSection.vue";
import ProgressPanel from "./components/ProgressPanel.vue";
import ResultPanel from "./components/ResultPanel.vue";
import ErrorPanel from "./components/ErrorPanel.vue";

// Ruby -> JS: пушится через window.exporter.* (см. ExportDialog), JS -> Ruby:
// window.sketchup.*. В обычном браузере моста нет: секции видны, но
// предпросмотр не строится (панель показывает подсказку).
const state = reactive({
  mode: "idle", // idle | exporting | done | error
  message: null,
  stats: null,
  warnings: [],
  glb_name: null,
  web_dir_name: null,
  single_file_name: null,
  single_file_bytes: null,
  model_name: "",
  selection_count: null,
  output_name: null,
  default_folder: null,
});

const progress = reactive({ active: false, pct: 0, stage: "", current: null, label: "Экспорт" });

const preview = reactive({
  status: "empty", // empty|building|assembling|ready|error|too_large|empty_selection
  pct: 0,
  current: null,
  message: null,
  bytes: null,
  objects: null,
  triangles: null,
  stale: false, // опции изменились, предпросмотр устарел
});

const scope = ref("all");
const folder = ref("");
const includeHidden = ref(false);
const singleFile = ref(true);
const webPackage = ref(true);
const previewTextures = ref(false);
const selectionPids = ref([]);

const previewPane = ref(null);
const offline = computed(() => !inSketchUp());

const exporting = computed(() => state.mode === "exporting");

// ---------------------------------------------------------- preview flow

let refreshTimer = 0;

function schedulePreviewRefresh(delay = 400) {
  clearTimeout(refreshTimer);
  refreshTimer = setTimeout(() => {
    refreshTimer = 0;
    refreshPreview();
  }, delay);
}

function refreshPreview() {
  clearTimeout(refreshTimer);
  refreshTimer = 0;
  if (!inSketchUp()) return;
  if (state.mode === "exporting") {
    preview.stale = true;
    return;
  }
  preview.stale = false;
  preview.status = "building";
  preview.pct = 0;
  preview.current = null;
  callSketchUp(
    "preview_refresh",
    JSON.stringify({
      scope: scope.value,
      include_hidden: includeHidden.value,
      embed_textures: previewTextures.value,
    })
  );
}

// Сборка data:-URI из чанков, затем загрузка в движок.
let previewChunks = null;

function receivePreviewStart(total) {
  previewChunks = new Array(total);
}

function receivePreviewChunk(index, b64) {
  if (previewChunks) previewChunks[index] = b64;
}

function receivePreviewEnd() {
  if (!previewChunks) return;
  const url = "data:model/gltf-binary;base64," + previewChunks.join("");
  previewChunks = null;
  preview.status = "ready";
  preview.message = null;
  preview.bytes = null;
  previewPane.value?.load(url);
}

function receivePreviewStatus(s) {
  if (s.status === "idle") {
    // Предпросмотр отменён (вытеснён экспортом) - вернуться к пустому состоянию.
    if (preview.status === "building" || preview.status === "assembling") preview.status = "empty";
    return;
  }
  preview.status = s.status;
  if (s.pct !== undefined) preview.pct = s.pct;
  preview.current = s.current ?? null;
  preview.message = s.message ?? null;
  preview.bytes = s.bytes ?? null;
}

// ---------------------------------------------------- Ruby -> JS bridge

function receiveState(s) {
  Object.assign(state, s);
  if (s.default_folder && !folder.value) folder.value = s.default_folder;
  progress.active = false;
  // После экспорта предпросмотр мог устареть (изменились опции во время
  // экспорта) - перестраиваем с текущими настройками.
  if (s.mode === "done") schedulePreviewRefresh(300);
}

function receiveProgress(p) {
  progress.active = true;
  progress.pct = p.pct;
  progress.stage = p.stage;
  progress.current = p.current;
  progress.label = p.label;
}

function receiveSelection(s) {
  state.selection_count = s.count;
  selectionPids.value = s.pids || [];
  if (preview.status === "ready") previewPane.value?.setSelection(selectionPids.value);
}

function setOutputFolder(p) {
  folder.value = p;
}

onMounted(() => {
  window.exporter = {
    receiveState,
    setOutputFolder,
    receiveProgress,
    receivePreviewStatus,
    receivePreviewStart,
    receivePreviewChunk,
    receivePreviewEnd,
    receiveSelection,
  };
  callSketchUp("dialog_ready");
  schedulePreviewRefresh(150);
});

onBeforeUnmount(() => clearTimeout(refreshTimer));

// Опции экспорта влияют на содержимое предпросмотра - перестраиваем.
watch([scope, includeHidden, previewTextures], () => {
  if (preview.status === "ready") preview.stale = true;
  schedulePreviewRefresh();
});

// В режиме «Только выделенное» предпросмотр следит за выделением.
watch(selectionPids, () => {
  if (scope.value === "selection") schedulePreviewRefresh();
});

// --------------------------------------------------------- JS -> Ruby

function doExport() {
  progress.active = true;
  progress.pct = 0;
  progress.stage = "Подготовка";
  progress.current = null;
  progress.label = "Экспорт";
  callSketchUp(
    "export_start",
    JSON.stringify({
      scope: scope.value,
      folder: folder.value,
      include_hidden: includeHidden.value,
      single_file: singleFile.value,
      web_package: webPackage.value,
    })
  );
}

function browse() {
  callSketchUp("browse_output", folder.value);
}

function closeDialog() {
  callSketchUp("close");
}
</script>

<template>
  <div class="flex h-full min-h-0 bg-zinc-100">
    <PreviewPane
      ref="previewPane"
      :status="preview.status"
      :pct="preview.pct"
      :current="preview.current"
      :message="preview.message"
      :bytes="preview.bytes"
      :objects="preview.objects"
      :triangles="preview.triangles"
      :textures="previewTextures"
      :can-refresh="!exporting"
      :offline="offline"
      @select="(chain) => callSketchUp('preview_object_selected', ...chain)"
      @stats="(s) => { preview.objects = s.objects; preview.triangles = s.triangles; }"
      @error="(message) => { preview.status = 'error'; preview.message = message; }"
      @refresh="refreshPreview()"
      @toggle-textures="previewTextures = !previewTextures"
    />

    <aside class="flex w-[370px] shrink-0 flex-col border-l border-zinc-200 bg-zinc-50">
      <header class="border-b border-zinc-200 px-4 py-2.5">
        <h1 class="text-sm font-semibold text-zinc-800">Экспорт 3D</h1>
        <p class="truncate text-[11px] text-zinc-500">
          {{ state.model_name || "Нет открытой модели" }}
        </p>
      </header>

      <div class="flex-1 space-y-4 overflow-y-auto p-4">
        <ScopeSection v-model:scope="scope" :selection-count="state.selection_count" :disabled="exporting" />
        <OutputSection
          v-model:folder="folder"
          v-model:single-file="singleFile"
          v-model:web-package="webPackage"
          v-model:include-hidden="includeHidden"
          :output-name="state.output_name || ''"
          :disabled="exporting"
          @browse="browse"
        />

        <ProgressPanel
          v-if="exporting || progress.active"
          :pct="progress.pct"
          :stage="progress.stage"
          :current="progress.current"
          :label="progress.label"
          @cancel="callSketchUp('export_cancel')"
        />

        <ErrorPanel v-if="state.mode === 'error'" :message="state.message" />

        <p v-if="preview.stale" class="text-[11px] text-amber-600">
          Предпросмотр устарел — обновится после текущей операции.
        </p>

        <ResultPanel
          v-if="state.mode === 'done' && state.stats"
          :stats="state.stats"
          :warnings="state.warnings"
          :glb-name="state.glb_name"
          :web-dir-name="state.web_dir_name"
          :single-file-name="state.single_file_name"
          :single-file-bytes="state.single_file_bytes"
          @open-viewer="callSketchUp('open_viewer')"
          @open-folder="callSketchUp('open_folder')"
          @open-html="callSketchUp('open_html')"
        />
      </div>

      <footer class="flex items-center gap-2 border-t border-zinc-200 p-3">
        <button
          type="button"
          :disabled="exporting"
          class="rounded-md bg-sky-600 px-5 py-1.5 text-xs font-semibold text-white hover:bg-sky-500 disabled:opacity-50"
          @click="doExport"
        >
          Экспорт
        </button>
        <button
          type="button"
          class="rounded-md border border-zinc-300 bg-white px-4 py-1.5 text-xs font-medium text-zinc-700 hover:bg-zinc-100"
          @click="closeDialog"
        >
          Закрыть
        </button>
        <span class="flex-1"></span>
        <span v-if="preview.stale" class="rounded-full bg-amber-100 px-2 py-0.5 text-[10px] text-amber-700">
          предпросмотр устарел
        </span>
      </footer>
    </aside>
  </div>
</template>
